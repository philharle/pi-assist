map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    server_name FQDN.server.com;

    # These shouldn't need to be changed
    listen [::]:80 default_server ipv6only=off;
    return 301 https://$host$request_uri:443;
}

server {
    server_name FQDN.server.com;

    # Ensure these lines point to your SSL certificate and key
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    # Ensure this line points to your dhparams file
    ssl_dhparam /etc/nginx/ssl/dhparams.pem;
    # If issues with missing file run
    # sudo openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
    # or if this is too CPU intensive on a RaspberryPi then run
    # sudo openssl dhparam -dsaparam -out /etc/nginx/ssl/dhparam.pem 4096

    # These shouldn't need to be changed
    listen [::]:443 default_server ipv6only=off; # if your nginx version is >= 1.9.5 you can also add the "http2" flag here
    add_header Strict-Transport-Security "max-age=31536000; includeSubdomains";
    ssl on;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    proxy_buffering off;

    location / {
        proxy_pass http://home-assistant:8123;
        proxy_set_header Host $host;
        proxy_redirect http:// https://;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
   }
}
