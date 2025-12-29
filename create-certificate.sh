#!/bin/bash

# 创建自签名代码签名证书脚本
# 用于解决每次构建都需要重新授权的问题

set -e

CERT_NAME="QuiteNote Developer"
CERT_EMAIL="quitenote@localhost"
CERT_CN="QuiteNote Developer ID"

echo "=== 创建自签名代码签名证书 ==="
echo ""

# 检查证书是否已存在
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✅ 证书 '$CERT_NAME' 已存在"
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

echo "📝 创建证书配置文件..."

# 创建证书配置
cat > /tmp/Certificate.certSigningRequest << EOF
[req]
default_bits = 2048
distinguished_name = req_dn
x509_extensions = v3_ca
prompt = no

[req_dn]
CN = $CERT_CN
emailAddress = $CERT_EMAIL
O = QuiteNote
OU = Development
C = US

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = critical,codeSigning
EOF

echo "🔐 生成私钥和证书..."
# 生成私钥和自签名证书（有效期10年）
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /tmp/Certificate.key \
    -out /tmp/Certificate.crt \
    -days 3650 \
    -subj "/CN=$CERT_CN/emailAddress=$CERT_EMAIL/O=QuiteNote/OU=Development/C=US" \
    -extensions v3_ca \
    -config <(cat /tmp/Certificate.certSigningRequest <(printf '[v3_ca]\nkeyUsage = critical,digitalSignature,keyEncipherment\nextendedKeyUsage = critical,codeSigning'))

echo "📦 导入证书到钥匙串..."
# 创建 PKCS12 格式（带私钥）
openssl pkcs12 -export -out /tmp/Certificate.p12 \
    -inkey /tmp/Certificate.key \
    -in /tmp/Certificate.crt \
    -passout pass:quitenote

# 导入到登录钥匙串
security import /tmp/Certificate.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -P quitenote \
    -T /usr/bin/codesign

# 设置证书信任为代码签名
security set-trust -r trustAsRoot -p basic -p codeSigning -k ~/Library/Keychains/login.keychain-db \
    "$(openssl x509 -in /tmp/Certificate.crt -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"

echo ""
echo "✅ 证书创建完成！"
echo ""
echo "证书信息："
openssl x509 -in /tmp/Certificate.crt -noout -subject -issuer
echo ""

# 清理临时文件
rm -f /tmp/Certificate.*

echo "现在可以运行 ./build-app.sh 进行构建，应用将使用此证书签名。"
