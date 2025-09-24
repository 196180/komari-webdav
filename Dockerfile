FROM ghcr.io/komari-monitor/komari:latest

WORKDIR /app

RUN apk add --update --no-cache python3 py3-pip curl lsof

RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"
RUN pip install --no-cache-dir requests webdavclient3

RUN mkdir -p /app/data && chmod -R 777 /app/data
RUN chmod -R 775 /app
RUN mkdir -p /app/sync

COPY sync_data.sh /app/sync/
RUN chmod +x /app/sync/sync_data.sh

EXPOSE 25774

CMD ["/bin/sh", "-c", "/app/sync/sync_data.sh & sleep 10 && exec /app/komari server"]
