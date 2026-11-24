"""Apply the game's square-cell, 16-step YCoCg pixel post-process to a cover render."""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

def smoothstep(start, end, values):
    t = np.clip((values - start) / (end - start), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def pixel_post(image):
    color = np.asarray(image.convert('RGB'), dtype=np.float32)[1::2, 1::2] / 255.0
    luma_weights = np.array([0.299, 0.587, 0.114], dtype=np.float32)
    light = color @ luma_weights
    padded = np.pad(light, 1, mode='edge')
    left, right = padded[1:-1, :-2], padded[1:-1, 2:]
    up, down = padded[:-2, 1:-1], padded[2:, 1:-1]
    brighter = np.maximum.reduce([left, right, up, down]) - light
    dark_side = smoothstep(0.14, 0.16, brighter)
    color *= 1 - (0.4 * dark_side[..., None])
    color = 1.15 * color - 0.15 * (color @ luma_weights)[..., None]
    color = np.clip((color - 0.5) * 1.05 + 0.5, 0, 1)

    ramp_x = np.where((right - light) * (light - left) > 0,
                      np.minimum(abs(right - light), abs(light - left)), 0)
    ramp_y = np.where((down - light) * (light - up) > 0,
                      np.minimum(abs(down - light), abs(light - up)), 0)
    gradient = smoothstep(0.001, 0.006, np.maximum(ramp_x, ramp_y)) * (1 - dark_side)
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])
    yi, xi = np.indices(light.shape)
    threshold = (bayer[yi % 4, xi % 4] + 0.5) / 16 - 0.5

    red, green, blue = np.moveaxis(color, -1, 0)
    luminance = 0.25 * red + 0.5 * green + 0.25 * blue
    luminance = np.floor(luminance * 15 + 0.5 + threshold * 0.8 * gradient) / 15
    co = np.floor((red - blue) * 32 + 0.5) / 64
    cg = np.floor((-0.25 * red + 0.5 * green - 0.25 * blue) * 64 + 0.5) / 64
    graded = np.stack((luminance + co - cg, luminance + cg, luminance - co - cg), axis=-1)
    return Image.fromarray(np.rint(np.clip(graded, 0, 1) * 255).astype(np.uint8))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('render', type=Path, help='960 × 540 PNG from render_slime_pub_room.py')
    parser.add_argument('output', type=Path, nargs='?', default=Path(__file__).resolve().parents[1] / 'slime-pub-room.png')
    args = parser.parse_args()
    with Image.open(args.render) as image:
        if image.size != (960, 540):
            parser.error('the input render must be 960 × 540')
        pixel_post(image).save(args.output, optimize=True)
