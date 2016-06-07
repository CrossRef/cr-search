FROM ruby:2.1

COPY . /app
COPY ./conf/app.json.docker /app/conf/app.json
WORKDIR /app

RUN bundle install
