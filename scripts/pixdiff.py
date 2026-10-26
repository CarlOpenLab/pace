#!/usr/bin/env python3
"""Pixel comparison for iOS screenshots, pure Python (no PIL, no sips).

    pixdiff.py old.png new.png [--skip-top N] [--skip-bottom N] [--tolerance 2]

Two screenshots of the same screen, same simulator, same data, same scroll
position. Everything outside the content region is ignored: by default the
status bar band (its clock changes every minute) and the bottom home bar.

Reports the largest per-channel difference and how many pixels exceed the
tolerance, so "the default-size appearance did not change" is a number rather
than an opinion. Exit code 0 when every pixel is inside tolerance.
"""
import struct
import sys
import zlib


def read_png(path):
    """Decode an 8-bit non-interlaced PNG to (w, h, channels, bytearray of RGB(A))."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    pos = 8
    w = h = depth = ctype = interlace = None
    idat = bytearray()
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctag == b"IHDR":
            w, h, depth, ctype, _comp, _filt, interlace = struct.unpack(">IIBBBBB", chunk)
        elif ctag == b"IDAT":
            idat += chunk
        elif ctag == b"IEND":
            break
    if depth != 8:
        raise ValueError(f"only 8-bit PNGs supported (got {depth})")
    if interlace != 0:
        raise ValueError("interlaced PNG not supported")
    chans = {0: 1, 2: 3, 4: 2, 6: 4}.get(ctype)
    if chans is None:
        raise ValueError(f"unsupported colour type {ctype}")

    raw = zlib.decompress(bytes(idat))
    stride = w * chans
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 0:
            pass
        elif f == 1:
            for i in range(chans, stride):
                line[i] = (line[i] + line[i - chans]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                left = line[i - chans] if i >= chans else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - chans] if i >= chans else 0
                b = prev[i]
                c = prev[i - chans] if i >= chans else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        else:
            raise ValueError(f"bad filter type {f} on row {y}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, chans, out


def main():
    args = sys.argv[1:]
    skip_top, skip_bottom, tolerance = 0, 0, 2
    paths = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--skip-top":
            skip_top = int(args[i + 1]); i += 2; continue
        if a == "--skip-bottom":
            skip_bottom = int(args[i + 1]); i += 2; continue
        if a == "--tolerance":
            tolerance = int(args[i + 1]); i += 2; continue
        paths.append(a); i += 1
    if len(paths) != 2:
        print(__doc__)
        return 2

    wa, ha, ca, pa = read_png(paths[0])
    wb, hb, cb, pb = read_png(paths[1])
    if (wa, ha) != (wb, hb):
        print(f"尺寸不同：{wa}x{ha} 与 {wb}x{hb}")
        return 2
    if min(ca, cb) < 3:
        print(f"需要 RGB 或 RGBA 图，拿到 {ca} 与 {cb} 通道")
        return 2

    top = max(0, skip_top)
    bottom = ha - max(0, skip_bottom)
    overs = 0
    worst = 0
    worst_at = None
    compared = 0
    sa = wa * ca
    sb = wb * cb
    for y in range(top, bottom):
        ra = pa[y * sa:(y + 1) * sa]
        rb = pb[y * sb:(y + 1) * sb]
        for px in range(wa):
            ia = px * ca
            ib = px * cb
            d = max(abs(ra[ia] - rb[ib]), abs(ra[ia + 1] - rb[ib + 1]), abs(ra[ia + 2] - rb[ib + 2]))
            compared += 1
            if d > tolerance:
                overs += 1
            if d > worst:
                worst = d
                worst_at = (px, y)

    print(f"比对像素 {compared:,}  最大通道差 {worst}  超过容差 {overs:,} 个（容差 {tolerance}，通道 {ca}/{cb}）")
    if worst > tolerance and worst_at:
        print(f"最大差异在 x={worst_at[0]} y={worst_at[1]}"
              f"（距顶部 {worst_at[1] - top}；那一带若是状态栏或调试条，加 --skip-top）")
    if overs == 0:
        print("结果：一致")
        return 0
    print(f"结果：不一致，{overs / compared * 100:.3f}% 的像素超出容差")
    return 1


if __name__ == "__main__":
    sys.exit(main())
