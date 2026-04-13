#!/bin/bash

domain="autork01.menghuan168.ru"
email="menghuan1866@gmail.com"
WEBROOT="/var/www/html"

echo "===== 全自动生产部署（Reality伪装专用）====="

# 1. 安装 nginx
if ! command -v nginx &> /dev/null; then
    apt update -y
    apt install -y nginx
fi

systemctl enable nginx
systemctl start nginx

# 2. 安装 certbot
if ! command -v certbot &> /dev/null; then
    apt install -y certbot python3-certbot-nginx
fi

# 3. 防火墙（如果有）
if command -v ufw &> /dev/null; then
    ufw allow 80
    ufw allow 443
fi

# 4. 初始化站点（避免 certbot 报错）
mkdir -p $WEBROOT
if [ ! -f "$WEBROOT/index.html" ]; then
    echo "<h1>init</h1>" > $WEBROOT/index.html
fi

systemctl reload nginx

# 5. 申请证书（仅第一次）
if [ ! -d "/etc/letsencrypt/live/$domain" ]; then
    echo ">>> 申请 SSL 证书"
    certbot --nginx -d $domain --non-interactive --agree-tos -m $email
else
    echo ">>> 证书已存在，跳过"
fi

# 6. 写 nginx（挑战模式 + 反探测）
cat > /etc/nginx/sites-enabled/default <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain;

    root $WEBROOT;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    # === 反探测（基础）===
    if (\$http_user_agent ~* (curl|wget|python|scan|bot)) {
        return 403;
    }

    location / {
        if (\$http_cookie !~* "cf_clearance=ok") {
            return 302 /index.html;
        }
        try_files \$uri \$uri/ /home.html;
    }

    location = /index.html {
        try_files /index.html =404;
    }

    location = /home {
        rewrite ^ /home.html break;
    }
}
EOF

# 7. 部署假站（挑战页）
cd $WEBROOT || exit
rm -rf ./*

cat > index.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
<title>Just a moment...</title>
<link rel="icon" href="/favicon.ico">
<style>
body{font-family:Arial;text-align:center;margin-top:120px;background:#f6f7f9;}
.loader{
border:6px solid #eee;
border-top:6px solid orange;
border-radius:50%;
width:50px;height:50px;
animation:spin 1s linear infinite;
margin:auto;
}
@keyframes spin{100%{transform:rotate(360deg);}}
</style>
</head>
<body>
<div class="loader"></div>
<h2>Just a moment...</h2>
<p>Checking your browser...</p>
<script>
setTimeout(function(){
document.cookie="cf_clearance=ok; path=/;";
location.href="/home";
},3000);
</script>
</body>
</html>
HTML

cat > /var/www/html/home.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Performance & Security | Cloudflare</title>

<link rel="icon" href="/favicon.ico">
<link rel="stylesheet" href="/assets/css/style.css">

<style>
body{
    margin:0;
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto;
    background:#f6f7f9;
    color:#333;
}
header{
    background:#ffffff;
    border-bottom:1px solid #e5e7eb;
    padding:15px 30px;
    display:flex;
    justify-content:space-between;
    align-items:center;
}
.logo{
    font-weight:bold;
    color:#f6821f;
    font-size:20px;
}
.nav a{
    margin-left:20px;
    text-decoration:none;
    color:#333;
    font-size:14px;
}
.hero{
    padding:60px 20px;
    text-align:center;
}
.hero h1{
    font-size:36px;
    margin-bottom:20px;
}
.hero p{
    font-size:16px;
    color:#666;
}
.section{
    max-width:1100px;
    margin:auto;
    padding:40px 20px;
    display:grid;
    grid-template-columns:repeat(auto-fit,minmax(250px,1fr));
    gap:20px;
}
.card{
    background:#fff;
    padding:25px;
    border-radius:12px;
    box-shadow:0 4px 12px rgba(0,0,0,0.06);
}
.footer{
    text-align:center;
    padding:30px;
    font-size:12px;
    color:#888;
}
</style>
</head>

<body>

<header>
<div class="logo">Cloudflare</div>
<div class="nav">
<a href="#">Products</a>
<a href="#">Solutions</a>
<a href="#">Developers</a>
<a href="#">Company</a>
</div>
</header>

<div class="hero">
<h1>Make everything you connect to the Internet secure, private, fast</h1>
<p>Cloudflare protects and accelerates any Internet application online.</p>
</div>

<div class="section">

<div class="card">
<h3>Global CDN</h3>
<p>Deliver content faster with our global edge network.</p>
</div>

<div class="card">
<h3>DDoS Protection</h3>
<p>Protect your applications from attacks and downtime.</p>
</div>

<div class="card">
<h3>Zero Trust</h3>
<p>Secure your workforce with identity-based access.</p>
</div>

<div class="card">
<h3>DNS Services</h3>
<p>Fast, reliable and secure DNS infrastructure.</p>
</div>

</div>

<div class="section">
<div class="card">
<h3>System Status</h3>
<p>All systems operational.</p>
</div>

<div class="card">
<h3>Network</h3>
<p>300+ cities worldwide connected.</p>
</div>

<div class="card">
<h3>Security</h3>
<p>Millions of threats blocked daily.</p>
</div>
</div>

<div class="footer">
© 2026 Cloudflare, Inc.
</div>

<script src="/assets/js/app.js"></script>

</body>
</html>
HTML

echo -e "User-agent: *\nDisallow:" > robots.txt
echo '<?xml version="1.0"?><urlset></urlset>' > sitemap.xml

wget -q -O favicon.ico https://www.cloudflare.com/favicon.ico

mkdir -p assets/js assets/css
echo "console.log('ok')" > assets/js/app.js

chown -R www-data:www-data $WEBROOT

# 8. 自动续期
(crontab -l 2>/dev/null | grep -q certbot) || \
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -

# 9. 重启 nginx
nginx -t && systemctl restart nginx

echo "===== 完成 ====="
echo ">>> 访问: https://$domain"