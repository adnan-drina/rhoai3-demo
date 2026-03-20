#!/usr/bin/env python3
"""RAG Document Ingestion — Create vector stores and index all scenario documents.

Fallback ingestion method when KFP pipelines are unavailable. Runs inside the
cluster (e.g., from a workbench or via oc exec) with direct LlamaStack API access.

Usage (from workbench or oc exec into lsd-rag pod):
    python3 rag-ingest.py

Usage (port-forwarded):
    LLAMA_STACK_URL=http://localhost:8321 python3 rag-ingest.py
"""
import os, sys, requests
from llama_stack_client import LlamaStackClient

LLAMA_STACK_URL = os.getenv("LLAMA_STACK_URL", "http://lsd-rag-service.private-ai.svc.cluster.local:8321")
MINIO_URL = os.getenv("MINIO_URL", "http://minio.minio-storage.svc.cluster.local:9000")

client = LlamaStackClient(base_url=LLAMA_STACK_URL)

scenarios = {
    "whoami": {
        "s3_prefix": "whoami",
        "files": ["adnan_drina_cv.pdf"]
    },
    "acme_corporate": {
        "s3_prefix": "acme",
        "files": [
            "ACME_01_ACME_DFO_Calibration_SOP_v1.9_(Tool_L-900_EUV).pdf",
            "ACME_02_PX-7_Lithography_Control_Plan_&_SPC_Limits.pdf",
            "ACME_03_L-900_Tool_Health_&_Predictive_Rules_(FMEA_Extract).pdf",
            "ACME_04_Scanner_&_Metrology_Test_Recipe_Handbook.pdf",
            "ACME_05_Trouble_Response_Playbook_(Tier-1-Tier-2).pdf",
            "ACME_06_Reliability_Summary_Q3_FY25.pdf",
            "ACME_07_Corporate_Profile_&_Contact_Summary.pdf",
            "ACME_08_Product_&_Standards_Overview.pdf",
        ]
    },
}

SEP = "=" * 60
success_count = 0
fail_count = 0

for store_name, scenario in scenarios.items():
    print("\n" + SEP)
    print("Creating vector store: " + store_name)
    print(SEP)

    try:
        vs = client.vector_stores.create(
            name=store_name,
            extra_body={
                "embedding_model": "sentence-transformers/ibm-granite/granite-embedding-125m-english",
                "embedding_dimension": 768,
                "provider_id": "pgvector",
            }
        )
        print("  Store created: " + vs.id)
    except Exception as e:
        if "already exists" in str(e).lower():
            stores = list(client.vector_stores.list())
            vs = next((s for s in stores if s.name == store_name), None)
            if vs:
                print("  Store exists: " + vs.id)
            else:
                print("  Error: " + str(e))
                fail_count += 1
                continue
        else:
            print("  Error creating store: " + str(e))
            fail_count += 1
            continue

    for fname in scenario["files"]:
        minio_url = MINIO_URL + "/rag-documents/" + scenario["s3_prefix"] + "/" + fname
        print("  Processing: " + fname)
        try:
            resp = requests.get(minio_url, timeout=60)
            resp.raise_for_status()
            tmp_path = "/tmp/" + fname
            with open(tmp_path, "wb") as f:
                f.write(resp.content)
            print("    Downloaded " + str(len(resp.content)) + " bytes")

            with open(tmp_path, "rb") as f:
                file_info = client.files.create(file=(fname, f), purpose="assistants")
            print("    Uploaded: " + file_info.id)

            vs_file = client.vector_stores.files.create(
                vector_store_id=vs.id,
                file_id=file_info.id,
                chunking_strategy={
                    "type": "static",
                    "static": {"max_chunk_size_tokens": 512, "chunk_overlap_tokens": 100}
                }
            )
            print("    Indexed: status=" + vs_file.status)
            success_count += 1
            os.remove(tmp_path)
        except Exception as e:
            print("    Error: " + str(e))
            fail_count += 1

    print("  Done: " + store_name)

print("\n" + SEP)
print("INGESTION COMPLETE")
print(SEP)
stores = list(client.vector_stores.list())
for vs in stores:
    fc = vs.file_counts
    done = fc.completed if hasattr(fc, "completed") else 0
    print("  " + str(vs.name).ljust(20) + " id=" + vs.id + " files=" + str(done))

print(f"\n  {success_count} files indexed, {fail_count} failures")
sys.exit(1 if fail_count > 0 else 0)
