FROM python:3.12-slim

RUN pip install --no-cache-dir \
    flask \
    numpy \
    pandas \
    scipy \
    sympy \
    matplotlib

COPY executor.py /app/executor.py

WORKDIR /app
EXPOSE 8050

CMD ["python", "executor.py"]
