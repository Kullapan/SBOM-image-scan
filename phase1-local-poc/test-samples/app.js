const express = require('express');
const _ = require('lodash');

const app = express();
const port = 3000;

app.get('/health', (req, res) => {
    res.json({ status: 'UP', message: 'Sample Payment API running' });
});

app.listen(port, () => {
    console.log(`Sample app running on port ${port}`);
});
