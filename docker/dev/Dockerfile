# Wello Forms - development image
# Source code is bind-mounted at /app; gems and node_modules live in named volumes.
FROM ruby:4.0.9-alpine AS download

WORKDIR /fonts

RUN apk --no-cache add wget unzip && \
    wget https://github.com/satbyy/go-noto-universal/releases/download/v7.0/GoNotoKurrent-Regular.ttf && \
    wget https://github.com/satbyy/go-noto-universal/releases/download/v7.0/GoNotoKurrent-Bold.ttf && \
    wget https://github.com/impallari/DancingScript/raw/master/fonts/DancingScript-Regular.otf && \
    wget -O /model.onnx "https://github.com/docusealco/fields-detection/releases/download/2.0.0/model_704_int8.onnx" && \
    wget -O pdfium-linux.zip "https://github.com/docusealco/pdfium-binaries/releases/download/20260920/pdfium-musl-$(uname -m).zip" && \
    mkdir -p /pdfium-linux && unzip -q pdfium-linux.zip -d /pdfium-linux

FROM ruby:4.0.9-alpine

ENV RAILS_ENV=development \
    NODE_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    OPENSSL_CONF=/etc/openssl_legacy.cnf \
    VIPS_MAX_COORD=17000 \
    VIPS_BLOCK_UNTRUSTED=1

RUN apk upgrade --no-cache ca-certificates-bundle && \
    apk add --no-cache build-base git bash tzdata nodejs yarn \
      libpq libpq-dev postgresql-client yaml-dev sqlite-dev \
      vips onnxruntime leptonica jemalloc font-liberation font-carlito

RUN printf '.include = /etc/ssl/openssl.cnf\n\n[provider_sect]\ndefault = default_sect\nlegacy = legacy_sect\n\n[default_sect]\nactivate = 1\n\n[legacy_sect]\nactivate = 1\n' >> /etc/openssl_legacy.cnf

COPY --from=download /fonts/ /fonts/
COPY --from=download /pdfium-linux/lib/libpdfium.so /usr/lib/libpdfium.so
COPY --from=download /model.onnx /opt/model.onnx

RUN mkdir -p /usr/share/fonts/noto/bold && \
    ln -s /fonts/GoNotoKurrent-Regular.ttf /usr/share/fonts/noto/ && \
    ln -s /fonts/GoNotoKurrent-Bold.ttf /usr/share/fonts/noto/bold/ && fc-cache -f

WORKDIR /app

COPY docker/dev/entrypoint.sh /usr/local/bin/wello-entrypoint
RUN chmod +x /usr/local/bin/wello-entrypoint

ENTRYPOINT ["wello-entrypoint"]
EXPOSE 3000 3035
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "-b", "tcp://0.0.0.0:3000"]
