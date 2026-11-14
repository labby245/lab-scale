"""Converts a RealPLKSR (+ DySample) checkpoint into a realesrgan-ncnn-vulkan model.

Usage: python export_realplksr.py <weights.safetensors> <out-dir> <stem>

Writes <out-dir>/<stem>.param and <stem>.bin. The weights are not touched;
three parts of the graph are spelled differently so ncnn can run them, and the
script checks the rewritten network against the original before exporting:

- PLKConv2d writes into a slice of its input in eval mode; here it is a
  split + concat, which is what it does in training mode anyway.
- DySample builds its sampling grid from torch.arange of the feature size,
  which a trace would freeze at the export size, and samples all groups as
  one batch, which ncnn (no batch axis) cannot. Here the grid comes from a
  cumulative sum over the input, so it follows any tile size, and each group
  is sampled on its own.
- repeat_interleave on the 3 input channels is a plain concat of slices.

realesrgan-ncnn-vulkan feeds the blob "data" and reads "output"; pnnx names
them in0/out0, so they are renamed in the .param.
"""

import os
import shutil
import sys
import tempfile

import pnnx
import spandrel
import torch
import torch.nn as nn
import torch.nn.functional as F
from spandrel.architectures.__arch_helpers.dysample import DySample
from spandrel.architectures.PLKSR.__arch.RealPLKSR import PLKConv2d


def plk_forward(self, x):
    return torch.cat([self.conv(x[:, : self.idx]), x[:, self.idx :]], dim=1)


def dysample_forward(self, x):
    s, groups = self.scale, self.groups
    offset = self.offset(x) * self.scope(x).sigmoid() * 0.5 + self.init_pos
    n = groups * s * s  # first n channels: x offsets, next n: y offsets
    ones = x[:, :1] * 0 + 1
    cx = torch.cumsum(ones, dim=3) - 0.5  # column index + 0.5
    cy = torch.cumsum(ones, dim=2) - 0.5  # row index + 0.5
    w = torch.sum(ones, dim=3, keepdim=True)
    h = torch.sum(ones, dim=2, keepdim=True)
    gx = 2 * (cx + offset[:, :n]) / w - 1
    gy = 2 * (cy + offset[:, n:]) / h - 1
    grid = F.pixel_shuffle(torch.cat([gx, gy], dim=1), s)  # [1, 2*groups, sH, sW]
    per_group = x.shape[1] // groups
    out = torch.cat(
        [
            F.grid_sample(
                x[:, k * per_group : (k + 1) * per_group],
                torch.cat(
                    [grid[:, k : k + 1], grid[:, groups + k : groups + k + 1]], dim=1
                ).permute(0, 2, 3, 1),
                mode="bilinear",
                padding_mode="border",
                align_corners=False,
            )
            for k in range(groups)
        ],
        dim=1,
    )
    return self.end_conv(out) if self.end_convolution else out


class Exportable(nn.Module):
    def __init__(self, net):
        super().__init__()
        self.net = net
        self.repeats = net.repeat_op.keywords["repeats"]

    def forward(self, x):
        rep = torch.cat(
            [x[:, c : c + 1] for c in range(3) for _ in range(self.repeats)], dim=1
        )
        return self.net.to_img(self.net.feats(x) + rep)


def rename_blobs(src, dst):
    names = {"in0": "data", "out0": "output"}
    with open(src) as f:
        lines = f.read().splitlines()
    out = lines[:2] + [
        " ".join(names.get(tok, tok) for tok in line.split()) for line in lines[2:]
    ]
    with open(dst, "w") as f:
        f.write("\n".join(out) + "\n")


def main():
    weights, out_dir, stem = sys.argv[1:4]
    net = spandrel.ModelLoader(device="cpu").load_from_file(weights).model.eval()
    if not isinstance(net.to_img, DySample) or net.repeat_op.keywords["repeats"] != 16:
        sys.exit("expected a 4x RealPLKSR with a DySample upsampler")

    probe = torch.rand(1, 3, 37, 53)  # odd sizes: catches a grid baked to one shape
    with torch.no_grad():
        reference = net(probe)
        PLKConv2d.forward = plk_forward
        DySample.forward = dysample_forward
        model = Exportable(net).eval()
        diff = (model(probe) - reference).abs().max().item()
    if diff > 1e-5:
        sys.exit(f"rewritten graph differs from the original by {diff}")
    print(f"rewrite matches the original (max abs diff {diff:.1e})")

    work = tempfile.mkdtemp()
    try:
        cwd = os.getcwd()
        os.chdir(work)
        try:
            # Two input sizes so pnnx keeps width and height dynamic.
            pnnx.export(
                model,
                "m.pt",
                (torch.rand(1, 3, 64, 64),),
                (torch.rand(1, 3, 96, 80),),
                fp16=False,
            )
        finally:
            os.chdir(cwd)
        os.makedirs(out_dir, exist_ok=True)
        rename_blobs(os.path.join(work, "m.ncnn.param"), os.path.join(out_dir, f"{stem}.param"))
        shutil.copyfile(os.path.join(work, "m.ncnn.bin"), os.path.join(out_dir, f"{stem}.bin"))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
