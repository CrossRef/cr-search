FROM ruby:2.1

COPY . /app
WORKDIR /app

RUN bundle install
