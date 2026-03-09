FROM registry.access.redhat.com/ubi9/python-311:latest

USER root

WORKDIR /app

COPY app/server.py /app/server.py

RUN pip install --no-cache-dir \
  fastmcp \
  kubernetes \
  sse-starlette

EXPOSE 8000

CMD ["python", "server.py"]
