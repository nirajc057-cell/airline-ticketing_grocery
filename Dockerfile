FROM ghcr.io/cirruslabs/flutter:3.44.0 AS flutter-builder

WORKDIR /source/flutter_app
COPY flutter_app/pubspec.yaml flutter_app/pubspec.lock ./
RUN flutter pub get
COPY flutter_app/ ./
RUN flutter build web --release --base-href /flutter/ --pwa-strategy=none

FROM node:22-alpine

ENV NODE_ENV=production \
    PORT=4782

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --chown=node:node . .
COPY --from=flutter-builder --chown=node:node /source/flutter_app/build/web /app/flutter_app/build/web
RUN mkdir -p /app/data && chown -R node:node /app/data

USER node

EXPOSE 4782
VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:4782/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"

CMD ["npm", "start"]
