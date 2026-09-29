FROM golang:1.15-alpine AS backend-builder

WORKDIR /usr/src/app

COPY backend/go.mod backend/go.sum ./

RUN go mod download

COPY backend/ .

ENV CGO_ENABLED=0

RUN CGO_ENABLED=0 go build -o server .

FROM node:20-alpine AS frontend-builder

WORKDIR /usr/src/app

COPY frontend/package*.json ./

RUN npm install --legacy-peer-deps

COPY frontend/ .

ARG REACT_APP_BACKEND_URL=/api

ENV REACT_APP_BACKEND_URL=$REACT_APP_BACKEND_URL

RUN npm run build

FROM nginx:alpine AS runtime

RUN apk add --no-cache go-init && \
    mkdir -p /run/nginx /etc/nginx/http.d /etc/nginx/conf.d /usr/src/app /var/lib/nginx

WORKDIR /usr/src/app

COPY --from=backend-builder /usr/src/app/server /usr/src/app/server

COPY --from=frontend-builder /usr/src/app/build /usr/share/nginx/html

COPY nginx.conf /etc/nginx/nginx.conf

RUN printf 'server {\n\
    listen 80;\n\
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
}\n' > /etc/nginx/http.d/default.conf && \
    chmod +x /usr/src/app/server

ENV PORT=8080 \
    REQUEST_ORIGIN=http://localhost \
    REDIS_HOST=redis_server \
    POSTGRES_HOST=postgres_server \
    POSTGRES_USER=postgres \
    POSTGRES_DATABASE=postgres

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD wget -qO- http://127.0.0.1/api/ping || exit 1

CMD ["sh", "-c", "mkdir -p /run/nginx && (/usr/src/app/server &) && nginx -g 'daemon off;'"]