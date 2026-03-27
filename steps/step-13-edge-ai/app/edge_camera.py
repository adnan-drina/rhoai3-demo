"""Edge Camera — Real-time face recognition at the edge.

Streamlit app with two modes:
1. Photo mode (st.camera_input) — take a single photo, run inference
2. Live mode (streamlit-webrtc) — real-time video with bounding box overlay

Designed to run on a phone browser via an OpenShift HTTPS Route.
The inference endpoint is a KServe v2 model server in the same namespace.
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
# ---------------------------------------------------------------------------
if mode == "\U0001f4f8 Photo":
    frame = st.camera_input("Point your camera at a face")
    uploaded = st.file_uploader("Or upload an image", type=["jpg", "jpeg", "png"])

    source = frame or uploaded
    if source is not None:
        img_bytes = source.getvalue()
        img_bgr = cv2.imdecode(
            np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR
        )

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
                st.info(
                    f"Check that the model server is running:\n\n"
                    f"`oc get inferenceservice face-recognition-edge -n edge-ai-demo`"
                )

# ---------------------------------------------------------------------------
# Live video mode — streamlit-webrtc
# ---------------------------------------------------------------------------
elif mode == "\U0001f3a5 Live Video":
    try:
        from streamlit_webrtc import webrtc_streamer, VideoProcessorBase
        import av

        class FaceDetector(VideoProcessorBase):
            def recv(self, frame: av.VideoFrame) -> av.VideoFrame:
                img_bgr = frame.to_ndarray(format="bgr24")
                try:
                    annotated, _ = detect_faces(img_bgr, ENDPOINT, CONFIDENCE)
                except Exception:
                    annotated = img_bgr
                return av.VideoFrame.from_ndarray(annotated, format="bgr24")

        ctx = webrtc_streamer(
            key="edge-face-detection",
            video_processor_factory=FaceDetector,
            rtc_configuration={
                "iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]
            },
            media_stream_constraints={"video": True, "audio": False},
        )

        st.caption(
            "Each video frame is sent to the edge model server for inference. "
            "Latency depends on network and model server load."
        )

        if not ctx.state.playing:
            st.info(
                "Click **START** above to begin live video. "
                "Your browser will ask for camera permission."
            )

    except ImportError:
        st.warning(
            "`streamlit-webrtc` is not installed. Use **Photo** mode instead, "
            "or rebuild the container with `streamlit-webrtc` in requirements.txt."
        )

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
