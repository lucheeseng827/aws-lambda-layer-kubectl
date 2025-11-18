const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Middleware
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Main endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Serverless Function on Kubernetes!',
    timestamp: new Date().toISOString(),
    hostname: process.env.HOSTNAME || 'unknown',
    version: '1.0.0'
  });
});

// Health check endpoint (required)
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

// Readiness check endpoint (required)
app.get('/ready', (req, res) => {
  res.status(200).json({ status: 'ready' });
});

// Echo endpoint
app.post('/echo', (req, res) => {
  res.json({
    message: 'Echo response',
    receivedData: req.body,
    timestamp: new Date().toISOString()
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(port, () => {
  console.log(`Serverless function listening on port ${port}`);
  console.log(`Health check: http://localhost:${port}/health`);
  console.log(`Ready check: http://localhost:${port}/ready`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    console.log('HTTP server closed');
  });
});
