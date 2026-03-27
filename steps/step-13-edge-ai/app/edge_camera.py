"""Edge Camera — Real-time face recognition at the edge.

Streamlit app with two modes:
1. Photo mode (st.camera_input) — take a single photo, run inference
2. Live mode (camera_input_live) — continuous capture at ~1 fps, no WebRTC needed

Performance optimizations (all Streamlit-recommended):
- @st.fragment for partial reruns (only the camera section rerenders)
- KServe v2 Binary Tensor Extension (raw bytes instead of JSON float arrays)
- Reduced capture resolution (320px — less data over mobile network)

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


def run_inference_and_display(img_bytes):
    """Decode image bytes, run inference, display annotated result."""
    img_bgr = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)

    t0 = time.monotonic()
    try:
        annotated, detections = detect_faces(img_bgr, ENDPOINT, CONFIDENCE)
        latency_ms = (time.monotonic() - t0) * 1000

        col1, col2 = st.columns([2, 1])
        with col1:
            st.image(
                cv2.cvtColor(annotated, cv2.COLOR_BGR2RGB),
                caption="Detection Results",
            )
        with col2:
            st.metric("Faces detected", len(detections))
            st.metric("Latency", f"{latency_ms:.0f} ms")
            for d in detections:
                icon = "\U0001f7e2" if d["class_name"] != "unknown_face" else "\U0001f534"
                st.write(f"{icon} **{d['class_name']}** — {d['confidence']:.0%}")

    except Exception as e:
        st.error(f"Inference failed: {e}")
        st.info(
            "Check that the model server is running:\n\n"
            "`oc get inferenceservice face-recognition-edge -n edge-ai-demo`"
        )


# ---------------------------------------------------------------------------
# Photo mode — st.camera_input + file upload fallback
# ---------------------------------------------------------------------------
if mode == "\U0001f4f8 Photo":
    frame = st.camera_input("Point your camera at a face")
    uploaded = st.file_uploader("Or upload an image", type=["jpg", "jpeg", "png"])

    source = frame or uploaded
    if source is not None:
        with st.spinner("Running inference at the edge..."):
            run_inference_and_display(source.getvalue())

# ---------------------------------------------------------------------------
# Live video mode — camera_input_live inside @st.fragment
# ---------------------------------------------------------------------------
elif mode == "\U0001f3a5 Live Video":

    @st.fragment
    def live_camera_fragment():
        """Fragment that reruns independently on each new camera frame.

        Only this section re-executes when a new frame arrives — the sidebar,
        header, and mode selector are not re-rendered. This is the Streamlit-
        recommended pattern for live/streaming UI sections.
        Ref: https://docs.streamlit.io/develop/concepts/architecture/fragments
        """
        from camera_input_live import camera_input_live

        image = camera_input_live(
            debounce=1500,
            width=320,
            show_controls=True,
        )

        if image is not None:
            run_inference_and_display(image.getvalue())
        else:
            st.info("Waiting for camera... Your browser will ask for camera permission.")

    st.caption(
        "Camera captures frames continuously over HTTPS. "
        "Each frame is sent to the edge model server for inference. "
        "No WebRTC or STUN/TURN servers needed."
    )
    live_camera_fragment()

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
