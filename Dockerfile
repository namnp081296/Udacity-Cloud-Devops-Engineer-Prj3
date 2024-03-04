FROM python:3.10-slim-buster

WORKDIR .

COPY ./analytics/requirements.txt requirements.txt

RUN pip install -r requirements.txt

CMD python app.py