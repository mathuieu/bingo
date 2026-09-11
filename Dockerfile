FROM python:3.14-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=80

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py grilles.py mots.py mots.txt ./
COPY templates ./templates

EXPOSE 80

CMD ["python", "app.py"]