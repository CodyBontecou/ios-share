FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY tsconfig.json ./
COPY src ./src

RUN npm install typescript && npx tsc && npm remove typescript

EXPOSE 3000

CMD ["node", "dist/server.js"]
