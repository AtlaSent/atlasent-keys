FROM nginx:alpine

# CORS-enabled, read-only server config (see the file's header).
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY . /usr/share/nginx/html

EXPOSE 80
