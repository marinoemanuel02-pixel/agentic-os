"""Real face detection on real footage, rendered as a vertical clip: what the narration says runs on today's AI.

Runs OpenCV's YuNet detector (no faking: every box is the model's output on that frame) on a section of a video,
draws thin corner brackets with the confidence and a running count of faces, crops a 9:16 window and writes an
H.264 clip into the render app. Run with the OpenCV venv (~/.aos/venvs/cv, installed with consent 2026-10-08).

Usage: ~/.aos/venvs/cv/Scripts/python.exe tools/detect.py <src video> <start s> <dur s> <crop x> <out id> [--pan x2] [--min 0.6]
  crop x: left edge of the 9:16 window in source pixels; --pan moves it to x2 over the clip (soft in-out).
"""
import os
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
MEDIA = Path(os.environ.get("AOS_VIDEO_MEDIA_ROOT", Path.home() / ".aos" / "video" / ROOT.name))
MODEL = Path.home() / ".aos" / "models" / "yunet" / "face_detection_yunet_2023mar.onnx"
CYAN = (230, 211, 95)  # BGR of #5FD3E6
INK = (234, 240, 242)


def soft(t: float) -> float:
    return t * t * (3 - 2 * t)


def bracket(img, x, y, w, h, color, k=0.28, th=2):
    lx, ly = int(w * k), int(h * k)
    for (ax, ay, bx, by) in ((x, y, x + lx, y), (x, y, x, y + ly), (x + w, y, x + w - lx, y), (x + w, y, x + w, y + ly),
                             (x, y + h, x + lx, y + h), (x, y + h, x, y + h - ly), (x + w, y + h, x + w - lx, y + h),
                             (x + w, y + h, x + w, y + h - ly)):
        cv2.line(img, (ax, ay), (bx, by), color, th, cv2.LINE_AA)


def main():
    args = sys.argv[1:]
    src, start, dur, cx, out_id = args[0], float(args[1]), float(args[2]), int(args[3]), args[4]
    pan_to = int(args[args.index("--pan") + 1]) if "--pan" in args else cx
    min_score = float(args[args.index("--min") + 1]) if "--min" in args else 0.6
    cap = cv2.VideoCapture(src)
    fps_in = cap.get(cv2.CAP_PROP_FPS) or 25
    W, H = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.set(cv2.CAP_PROP_POS_MSEC, start * 1000)
    det = cv2.FaceDetectorYN.create(str(MODEL), "", (W, H), min_score, 0.3, 5000)
    cw = int(H * 9 / 16)
    out = MEDIA / "app" / "public" / "clips" / f"{out_id}.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)
    # resample to 30 fps by frame time; source frames are read at their own rate
    n_out = int(round(dur * 30))
    ff = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", "1080x1920",
                           "-r", "30", "-i", "-", "-c:v", "libx264", "-crf", "16", "-preset", "slow", "-pix_fmt", "yuv420p",
                           str(out)], stdin=subprocess.PIPE)
    frame, t_frame, total_seen = None, -1.0, 0
    counts = []
    for k in range(n_out):
        t = start + k / 30
        while t_frame < t:
            ok, f = cap.read()
            if not ok:
                break
            frame, t_frame = f, cap.get(cv2.CAP_PROP_POS_MSEC) / 1000
        if frame is None:
            break
        _, faces = det.detect(frame)
        faces = [] if faces is None else faces
        x0 = int(cx + (pan_to - cx) * soft(k / max(1, n_out - 1)))
        x0 = max(0, min(W - cw, x0))
        crop = frame[:, x0:x0 + cw].copy()
        n_in = 0
        for fc in faces:
            x, y, w, h, score = int(fc[0]) - x0, int(fc[1]), int(fc[2]), int(fc[3]), float(fc[-1])
            if x + w < 0 or x > cw:
                continue
            n_in += 1
            bracket(crop, x, y, w, h, CYAN, th=2)
            cv2.putText(crop, f"{score:.2f}", (x, max(10, y - 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.32, CYAN, 1, cv2.LINE_AA)
        counts.append(n_in)
        big = cv2.resize(crop, (1080, 1920), interpolation=cv2.INTER_LANCZOS4)
        # running count, top left, in the film's mono style (drawn after the upscale so it stays sharp)
        cv2.putText(big, f"FACES DETECTED  {n_in:3d}", (60, 140), cv2.FONT_HERSHEY_DUPLEX, 1.0, INK, 2, cv2.LINE_AA)
        cv2.putText(big, "YuNet  |  OpenCV 5.0  |  live", (60, 185), cv2.FONT_HERSHEY_SIMPLEX, 0.75, CYAN, 1, cv2.LINE_AA)
        ff.stdin.write(big.tobytes())
    ff.stdin.close()
    ff.wait()
    print(f"{out_id}: {len(counts)} frames, faces per frame mean {np.mean(counts):.1f}, max {max(counts)} -> {out}")


if __name__ == "__main__":
    main()
