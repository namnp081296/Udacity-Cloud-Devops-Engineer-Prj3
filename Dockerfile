FROM python:3.10-slim-buster

WORKDIR /src

COPY ./analytics/requirements.txt requirements.txt

RUN pip install -r requirements.txt

# RUN export DB_USERNAME=postgres
# RUN export DB_PASSWORD=${POSTGRES_PASSWORD}
# RUN export DB_HOST=127.0.0.1
# RUN export DB_PORT=5433
# RUN export DB_NAME=project3db

CMD python app.py