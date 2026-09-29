FROM golang:1.15-alpine AS backend-builder

WORKDIR /usr/src/app

COPY backend/go.mod backend/go.sum ./
RUN go mod download

COPY backend/ .
ENV CGO_ENABLED=0 GOOS=linux
RUN go build -ldflags="-s -w" -o /usr/src/app/server ./...

FROM node:20-alpine AS frontend-builder

WORKDIR /usr/src/app

COPY frontend/package*.json ./
RUN npm install --legacy-peer-deps

ARG REACT_APP_BACKEND_URL=/api
ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL

COPY frontend/ .
RUN npm run build

FROM nginx:alpine AS runtime

RUN mkdir -p /run/nginx /etc/nginx/http.d /etc/nginx/conf.d /var/lib/nginx/tmp /usr/src/app && \
    addgroup -S appuser && adduser -S appuser -G appuser

COPY --from=backend-builder /usr/src/app/server /usr/src/app/server
COPY --from=frontend-builder /usr/src/app/build /usr/share/nginx/html

RUN chown -R appuser:appuser /usr/src/app /var/lib/nginx /run/nginx /var/cache/nginx

RUN printf 'server {\n\
    listen 80;\n\
    server_name _;\n\
\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
\n\
    location /api/ {\n\
        proxy_set_header Host $host;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_pass http://127.0.0.1:8080/;\n\
    }\n\
}\n' > /etc/nginx/http.d/default.conf

ENV PORT=8080 \
    REDIS_HOST=redis \
    POSTGRES_HOST=postgres \
    POSTGRES_USER=postgres \
    POSTGRES_DATABASE=postgres \
    REQUEST_ORIGIN=http://localhost

USER root

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -q --spider http://127.0.0.1/ || exit 1

CMD ["sh", "-c", "mkdir -p /run/nginx && (/usr/src/app/server &) && nginx -g 'daemon off;'"]