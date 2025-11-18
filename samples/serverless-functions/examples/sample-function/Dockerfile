FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY . .

# Expose port
EXPOSE 8080

# Health check endpoints required
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js || exit 1

# Run the application
CMD ["node", "server.js"]
