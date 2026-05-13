FROM python:3.12-alpine

WORKDIR /app
COPY docker/echo-server.py /app/echo-server.py

EXPOSE 8080
CMD ["python", "/app/echo-server.py"]
