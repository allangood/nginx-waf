# Nginx + ModSecurity WAF

When you run the container for the first time it will create all needed configuration files if they don't exists.
To run the WAF with Let's Encrypt and Maxmind GeoIP, this is an example to run it:

### Docker run command
Prepare your directories first:
```
mkdir -p /opt/nginx/{conf,logs,www}
```
Then run your docker container:
```
docker run --name nginx --net=host --restart=unless-stopped \
  -v /opt/nginx/conf:/etc/nginx \
  -v /etc/letsencrypt:/etc/letsencrypt:ro \
  -v /opt/nginx/logs:/var/log/nginx \
  -v /opt/nginx/www:/var/www \
  -v /var/lib/GeoIP:/var/lib/GeoIP \
  allangood/nginx-modsecurity:latest
```

### Docker compose example:
Prepare your directories first:
```
mkdir -p /opt/nginx/{conf,logs,www}
```
Create the docker-compose file with this content:
```
nginx:
    container_name: nginx
    image: allangood/nginx-modsecurity:latest
    restart: unless-stopped
    network_mode: host
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 80M
    volumes:
      - /opt/nginx:/etc/nginx
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/log/nginx:/var/log/nginx
      - /var/www:/var/www
      - /var/lib/GeoIP:/var/lib/GeoIP
    environment:
      - TZ="UTC"
```
Then run docker-compose:
```
docker-compose -f <docker-compose-file.yaml> up -d
```
