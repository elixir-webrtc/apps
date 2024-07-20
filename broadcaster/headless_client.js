'use strict';

const puppeteer = require('puppeteer');

(async () => {
    const browser = await puppeteer.launch({
        // headless: false,
        args: [
            '--no-sandbox',
            '--use-fake-ui-for-media-stream',
            '--use-fake-device-for-media-stream'
        ]
    });
    
    try {
        const username = (process.env.USERNAME === undefined) ? 'admin' : process.env.USERNAME;
        const password = (process.env.PASSWORD === undefined) ? 'admin' : process.env.PASSWORD;
        const url = (process.env.URL === undefined) ? 'http://localhost:4000' : process.env.URL;
        const token = (process.env.TOKEN === undefined) ? 'example' : process.env.TOKEN;
      
        const page = await browser.newPage();
        await page.setViewport({width: 1280, height: 720});
        await page.authenticate({username: username, password: password});
        await page.goto(`${url}/admin/player`);
      
        // When button is available and initialized,
        // we can safely start streaming.
        await page.waitForSelector('button');
        await page.waitForFunction(() => {
          const button = document.getElementById('button');
          console.log(button);
          return button.onclick !== null;
        });
      
        await page.evaluate((url, token) => {
          document.getElementById('serverUrl').value = `${url}/api/whip`;
          document.getElementById('serverToken').value = token;
        }, url, token);
      
        await page.evaluate(() => {
          document.getElementById('button').click();
        });
    } catch {
      await browser.close();
    }
})();