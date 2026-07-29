# syntax=docker/dockerfile:1

# Stage 1 — build the app
FROM dhi.io/node:26-dev AS build

WORKDIR /app

COPY package*.json ./

# Reproducible, lockfile-exact install (vite must be a devDependency in package.json)
RUN npm ci --legacy-peer-deps

COPY . .

RUN npm run build

# Stage 2 — minimal runtime (hardened DHI base)
FROM dhi.io/node:26

WORKDIR /app

# Copy built assets and deps with correct ownership
COPY --from=build --chown=nonroot:nonroot /app/dist ./dist
COPY --from=build --chown=nonroot:nonroot /app/node_modules ./node_modules
COPY --from=build --chown=nonroot:nonroot /app/vite.preview.config.js ./vite.config.js

# DHI image runs as nonroot by default; explicit for clarity
USER nonroot

EXPOSE 4173

# Use exec form for proper signal handling
ENTRYPOINT ["node", "--no-warnings"]
CMD ["./node_modules/.bin/vite", "preview", "--host", "0.0.0.0", "--port", "4173"]
