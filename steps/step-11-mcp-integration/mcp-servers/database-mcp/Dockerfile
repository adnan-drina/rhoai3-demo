FROM registry.access.redhat.com/ubi9/nodejs-20:latest

WORKDIR /app

USER 0
COPY package*.json ./
RUN npm install --omit=dev

COPY app ./app
RUN chown -R 1001:0 /app && chmod -R g=u /app

USER 1001
ENV PORT=8080
EXPOSE 8080

CMD ["/bin/sh", "-c", "npx -y supergateway --stdio \"node app/index.js\" --port ${PORT:-8080}"]
