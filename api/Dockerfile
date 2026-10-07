# python:3.13-slim rather than 3.14: uvicorn still lists 3.14 support as experimental (checked 2026-10-07).
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Never run as root inside the container; Nomad still owns the netns and cgroups.
RUN useradd --system --uid 10001 --no-create-home api
USER api

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
