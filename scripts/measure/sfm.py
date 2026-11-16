"""Solve the cameras of the frames of one shot with COLMAP (plan 0005, R1).

    python3 scripts/measure/sfm.py FRAMES OUT [--focal F] [--frames A,B,C]

FRAMES is a folder of the frames of one shot of a video, in their order
(001.jpg, 002.jpg, ...): one camera for all of them. OUT gets the
database and the models of COLMAP, and cameras.json: the camera of each
frame of the largest model (with --frames, only of those frames). With
--focal, the focal length in pixels stays at F; else COLMAP finds it.

The frames of a shot: ffmpeg -ss START -i VIDEO -t SECONDS
-vf "fps=4,crop=W:H:X:Y" -q:v 2 FRAMES/%03d.jpg (the crop takes off
the black bands; ffmpeg -vf cropdetect finds them).
"""

import argparse
import pathlib
import sys

import pycolmap

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import save  # noqa: E402


def main():
    a = argparse.ArgumentParser()
    a.add_argument("frames")
    a.add_argument("out")
    a.add_argument("--focal", type=float)
    a.add_argument("--frames", dest="only")
    o = a.parse_args()

    out = pathlib.Path(o.out)
    out.mkdir(parents=True, exist_ok=True)
    db = out / "database.db"
    if db.exists():
        db.unlink()

    reader = pycolmap.ImageReaderOptions()
    reader.camera_model = "SIMPLE_RADIAL"
    if o.focal:
        from PIL import Image

        first = sorted(pathlib.Path(o.frames).glob("*.jpg"))[0]
        w, h = Image.open(first).size
        reader.camera_params = f"{o.focal},{w / 2},{h / 2},0"
    pycolmap.extract_features(db, o.frames, camera_mode=pycolmap.CameraMode.SINGLE, reader_options=reader)
    pycolmap.match_sequential(db)

    options = pycolmap.IncrementalPipelineOptions()
    if o.focal:
        options.ba_refine_focal_length = False
    models = pycolmap.incremental_mapping(db, o.frames, out, options=options)
    if not models:
        sys.exit("COLMAP found no model: the frames have too little overlap")
    rec = max(models.values(), key=lambda r: r.num_reg_images())

    only = set(o.only.split(",")) if o.only else None
    cams = {}
    for img in sorted(rec.images.values(), key=lambda i: i.name):
        if only and img.name not in only:
            continue
        cam = rec.cameras[img.camera_id]
        pose = img.cam_from_world()
        cams[img.name] = {
            "width": cam.width,
            "height": cam.height,
            "model": cam.model.name,
            "params": [float(p) for p in cam.params],
            "rotation": pose.rotation.matrix().tolist(),
            "translation": pose.translation.tolist(),
        }
    save(out / "cameras.json", cams)
    print(f"{rec.num_reg_images()} frames; {len(rec.points3D)} points; cameras.json: {len(cams)} frames")
    print(rec.summary())


if __name__ == "__main__":
    main()
