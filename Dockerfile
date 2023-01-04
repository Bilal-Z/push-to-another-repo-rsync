FROM alpine:latest

RUN apk add --no-cache git openssh-client
RUN chmod +x entrypoint.sh

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]