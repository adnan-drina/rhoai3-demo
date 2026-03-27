"""Edge Camera — Real-time face recognition at the edge.

Streamlit app with two modes:
1. Photo mode (st.camera_input) — take a single photo, see full annotated image
2. Live mode (camera_input_live) — continuous capture, compact detection results

Performance optimizations:
- KServe v2 Binary Tensor Extension (raw bytes instead of JSON float arrays)
- Reduced capture resolution (320px — less data over mobile network)
- Live mode shows text-only results to prevent mobile layout reflow

Designed to run on a phone browser via an OpenShift HTTPS Route.
Uses only HTTP/WebSocket — no STUN/TURN servers required.
"""

import os
import time

import cv2
import numpy as np
import streamlit as st

from inference import detect_faces, CLASSES, COLORS

ENDPOINT = os.environ.get(
    "FACE_RECOGNITION_ENDPOINT",
    "http://face-recognition-edge-predictor:8888/v2/models/face-recognition-edge/infer",
)
CONFIDENCE = float(os.environ.get("CONFIDENCE_THRESHOLD", "0.3"))

st.set_page_config(
    page_title="Edge AI — Face Recognition",
    page_icon="\U0001f4f7",
    layout="wide",
)

st.title("Edge AI — Face Recognition")
st.caption("YOLO11 on OpenVINO Model Server — inference at the edge, models from the datacenter")

mode = st.radio("Mode", ["\U0001f4f8 Photo", "\U0001f3a5 Live Video"], horizontal=True)

# ---------------------------------------------------------------------------
# Photo mode — st.camera_input + file upload fallback
# Full annotated image with bounding boxes.
# ---------------------------------------------------------------------------
if mode == "\U0001f4f8 Photo":
    frame = st.camera_input("Point your camera at a face")
    uploaded = st.file_uploader("Or upload an image", type=["jpg", "jpeg", "png"])

    source = frame or uploaded
    if source is not None:
        img_bytes = source.getvalue()
        img_bgr = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)

        with st.spinner("Running inference at the edge..."):
            t0 = time.monotonic()
            try:
                annotated, detections = detect_faces(img_bgr, ENDPOINT, CONFIDENCE)
                latency_ms = (time.monotonic() - t0) * 1000

                col1, col2 = st.columns([2, 1])
                with col1:
                    st.image(
                        cv2.cvtColor(annotated, cv2.COLOR_BGR2RGB),
                        caption="Detection Results",
                        use_container_width=True,
                    )
                with col2:
                    st.metric("Faces detected", len(detections))
                    st.metric("Latency", f"{latency_ms:.0f} ms")
                    for d in detections:
                        icon = "\U0001f7e2" if d["class_name"] != "unknown_face" else "\U0001f534"
                        st.write(f"{icon} **{d['class_name']}** — {d['confidence']:.0%}")

            except Exception as e:
                st.error(f"Inference failed: {e}")

# ---------------------------------------------------------------------------
# Live video mode — camera_input_live
# Compact text-only results to avoid layout reflow on mobile.
# The camera feed is the live view; detection metadata updates below it.
# ---------------------------------------------------------------------------
elif mode == "\U0001f3a5 Live Video":
    from camera_input_live import camera_input_live

    st.caption(
        "Camera captures frames continuously over HTTPS. "
        "Each frame is sent to the edge model server for inference."
    )

    image = camera_input_live(
        debounce=2000,
        width=320,
        show_controls=True,
        key="edge-cam",
    )

    if image is not None:
        img_bytes = image.getvalue()
        img_bgr = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)

        t0 = time.monotonic()
        try:
            _, detections = detect_faces(img_bgr, ENDPOINT, CONFIDENCE)
            latency_ms = (time.monotonic() - t0) * 1000

            if detections:
                faces = "  \n".join(
                    f"{'\\U0001f7e2' if d['class_name'] != 'unknown_face' else '\\U0001f534'} "
                    f"**{d['class_name']}** — {d['confidence']:.0%}"
                    for d in detections
                )
                st.success(
                    f"**{len(detections)} face(s)** detected — {latency_ms:.0f} ms  \n{faces}"
                )
            else:
                st.warning(f"No faces detected — {latency_ms:.0f} ms")

        except Exception as e:
            st.error(f"Inference error: {e}")
    else:
        st.info("Waiting for camera... Your browser will ask for camera permission.")

# ---------------------------------------------------------------------------
# Sidebar — edge metadata
# ---------------------------------------------------------------------------
with st.sidebar:
    st.header("Edge Deployment Info")
    st.code(ENDPOINT, language=None)
    st.caption(f"Confidence threshold: {CONFIDENCE}")
    st.markdown("---")
    st.markdown(
        "**Data flow:**\n\n"
        "Phone browser \u2192 Streamlit (edge) \u2192 "
        "OpenVINO OVMS (edge) \u2192 annotated result"
    )
    st.markdown(
        "**Model lifecycle:**\n\n"
        "Trained centrally (Step 12 pipeline) \u2192 "
        "Model Registry \u2192 MinIO \u2192 "
        "GitOps sync to edge"
    )
    st.markdown("---")
    st.markdown(
        "*This namespace simulates a Single Node OpenShift (SNO) "
        "edge deployment. In production, the edge runs on dedicated "
        "hardware at a remote site.*"
    )
