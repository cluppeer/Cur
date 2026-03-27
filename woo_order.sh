#!/bin/bash
# WooCommerce Site Tespit & Order Oluşturma Scripti
# Kullanım: SSH ile sunucuya bağlanıp çalıştırın
# ssh -p 65002 u593815790@93.127.218.20
# bash woo_order.sh

echo "=========================================="
echo "  WooCommerce Site Tespit Aracı"
echo "=========================================="
echo ""

# WordPress kurulumlarını bul
echo "[1] WordPress kurulumları aranıyor..."
WP_CONFIGS=$(find /home -name "wp-config.php" 2>/dev/null)

if [ -z "$WP_CONFIGS" ]; then
    echo "❌ Hiç WordPress kurulumu bulunamadı!"
    exit 1
fi

echo ""
echo "Bulunan WordPress kurulumları:"
echo "-------------------------------------------"

i=0
declare -a WOO_SITES=()

while IFS= read -r config; do
    WP_DIR=$(dirname "$config")
    SITE_URL=""

    # wp-config.php'den site URL'sini almaya çalış
    if command -v wp &>/dev/null; then
        SITE_URL=$(cd "$WP_DIR" && wp option get siteurl --skip-plugins --skip-themes 2>/dev/null)
    fi

    if [ -z "$SITE_URL" ]; then
        SITE_URL=$(grep -oP "define\s*\(\s*['\"]WP_SITEURL['\"]\s*,\s*['\"]([^'\"]+)" "$config" 2>/dev/null | head -1 | grep -oP "http[^'\"]+")
    fi

    # WooCommerce kurulu mu kontrol et
    WOO_PLUGIN="$WP_DIR/wp-content/plugins/woocommerce/woocommerce.php"
    if [ -f "$WOO_PLUGIN" ]; then
        WOO_VERSION=$(grep -oP "Version:\s*\K[0-9.]+" "$WOO_PLUGIN" 2>/dev/null)
        echo "  [$i] ✅ WooCommerce ($WOO_VERSION) - $WP_DIR"
        [ -n "$SITE_URL" ] && echo "       URL: $SITE_URL"
        WOO_SITES+=("$WP_DIR")
    else
        echo "  [$i] ⬜ WordPress (WooCommerce YOK) - $WP_DIR"
        [ -n "$SITE_URL" ] && echo "       URL: $SITE_URL"
    fi

    ((i++))
done <<< "$WP_CONFIGS"

echo ""
echo "-------------------------------------------"
echo "Toplam WordPress: $i | WooCommerce: ${#WOO_SITES[@]}"
echo "=========================================="

# WooCommerce sitesi yoksa çık
if [ ${#WOO_SITES[@]} -eq 0 ]; then
    echo "❌ WooCommerce kurulu site bulunamadı!"
    exit 1
fi

echo ""
echo "[2] WP-CLI kontrol ediliyor..."
if command -v wp &>/dev/null; then
    echo "✅ WP-CLI mevcut: $(wp --version 2>/dev/null)"

    echo ""
    echo "=========================================="
    echo "  Hangi sitede order oluşturmak istiyorsunuz?"
    echo "=========================================="

    for idx in "${!WOO_SITES[@]}"; do
        echo "  [$idx] ${WOO_SITES[$idx]}"
    done

    echo ""
    read -p "Site numarası seçin: " SITE_NUM

    SELECTED_DIR="${WOO_SITES[$SITE_NUM]}"
    echo ""
    echo "Seçilen: $SELECTED_DIR"
    echo ""

    # Mevcut ürünleri listele
    echo "[3] Mevcut ürünler listeleniyor..."
    cd "$SELECTED_DIR"
    wp wc product list --user=1 --fields=id,name,price,status --format=table 2>/dev/null || \
    wp post list --post_type=product --fields=ID,post_title,post_status --format=table 2>/dev/null

    echo ""
    read -p "Ürün ID girin (virgülle ayırın, örn: 12,45): " PRODUCT_IDS
    read -p "Her üründen kaç adet? (varsayılan: 1): " QTY
    QTY=${QTY:-1}

    echo ""
    echo "--- Müşteri Bilgileri ---"
    read -p "Ad: " FNAME
    read -p "Soyad: " LNAME
    read -p "E-posta: " EMAIL
    read -p "Telefon: " PHONE
    read -p "Adres: " ADDRESS
    read -p "Şehir: " CITY
    read -p "Ülke kodu (TR): " COUNTRY
    COUNTRY=${COUNTRY:-TR}

    echo ""
    echo "[4] Order oluşturuluyor..."

    # Line items JSON oluştur
    LINE_ITEMS=""
    IFS=',' read -ra IDS <<< "$PRODUCT_IDS"
    for pid in "${IDS[@]}"; do
        pid=$(echo "$pid" | tr -d ' ')
        if [ -n "$LINE_ITEMS" ]; then
            LINE_ITEMS="$LINE_ITEMS,"
        fi
        LINE_ITEMS="$LINE_ITEMS{\"product_id\":$pid,\"quantity\":$QTY}"
    done

    # WP-CLI ile order oluştur
    ORDER_JSON=$(cat <<EOF
{
    "status": "processing",
    "billing": {
        "first_name": "$FNAME",
        "last_name": "$LNAME",
        "email": "$EMAIL",
        "phone": "$PHONE",
        "address_1": "$ADDRESS",
        "city": "$CITY",
        "country": "$COUNTRY"
    },
    "shipping": {
        "first_name": "$FNAME",
        "last_name": "$LNAME",
        "address_1": "$ADDRESS",
        "city": "$CITY",
        "country": "$COUNTRY"
    },
    "line_items": [$LINE_ITEMS]
}
EOF
)

    # Temp dosyaya yaz ve WP-CLI ile oluştur
    TMPFILE=$(mktemp /tmp/woo_order_XXXXX.json)
    echo "$ORDER_JSON" > "$TMPFILE"

    echo ""
    echo "Order JSON:"
    cat "$TMPFILE"
    echo ""

    # WP-CLI wc komutu ile order oluştur
    RESULT=$(wp wc shop_order create --user=1 --porcelain \
        --billing="$(echo "$ORDER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['billing']))" 2>/dev/null)" \
        --line_items="[$LINE_ITEMS]" \
        --status=processing 2>&1)

    if [ $? -eq 0 ]; then
        echo "✅ Order başarıyla oluşturuldu! Order ID: $RESULT"
    else
        echo "WP-CLI wc komutu başarısız, alternatif yöntem deneniyor..."

        # Alternatif: wp eval ile doğrudan PHP kodu çalıştır
        wp eval "
        \$order = wc_create_order();
        \$order->set_status('processing');
        \$order->set_billing_first_name('$FNAME');
        \$order->set_billing_last_name('$LNAME');
        \$order->set_billing_email('$EMAIL');
        \$order->set_billing_phone('$PHONE');
        \$order->set_billing_address_1('$ADDRESS');
        \$order->set_billing_city('$CITY');
        \$order->set_billing_country('$COUNTRY');
        \$order->set_shipping_first_name('$FNAME');
        \$order->set_shipping_last_name('$LNAME');
        \$order->set_shipping_address_1('$ADDRESS');
        \$order->set_shipping_city('$CITY');
        \$order->set_shipping_country('$COUNTRY');
        \$ids = explode(',', '$PRODUCT_IDS');
        foreach(\$ids as \$pid) {
            \$product = wc_get_product(trim(\$pid));
            if(\$product) { \$order->add_product(\$product, $QTY); }
        }
        \$order->calculate_totals();
        \$order->save();
        echo 'Order ID: ' . \$order->get_id() . ' | Total: ' . \$order->get_total();
        " 2>&1

        if [ $? -eq 0 ]; then
            echo "✅ Order başarıyla oluşturuldu!"
        else
            echo "❌ Order oluşturulamadı. Hata yukarıda."
        fi
    fi

    rm -f "$TMPFILE"

else
    echo "⚠️  WP-CLI bulunamadı."
    echo ""
    echo "WP-CLI kurmak için:"
    echo "  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
    echo "  chmod +x wp-cli.phar"
    echo "  mv wp-cli.phar /usr/local/bin/wp"
    echo ""
    echo "Veya WooCommerce REST API kullanabilirsiniz."
    echo "Her WooCommerce sitesi için API key oluşturun:"
    echo "  WordPress Admin > WooCommerce > Ayarlar > Gelişmiş > REST API"
fi
