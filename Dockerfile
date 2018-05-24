FROM gliderlabs/alpine:3.6

RUN apk add --update docker bash && rm -rf /var/cache/apk/*

ADD . /app
ENTRYPOINT ["/app/entrypoint.sh"]
