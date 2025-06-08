import pandas as pd
import time
from tqdm import tqdm
import random
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException
from webdriver_manager.chrome import ChromeDriverManager
from bs4 import BeautifulSoup

def read_stock_tickers(file_path):
    tickers = []
    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if line:
                parts = line.split(',')
                if len(parts) == 2:
                    exchange, ticker = parts
                    tickers.append((exchange, ticker))
    return tickers

def setup_driver():
    chrome_options = Options()
    chrome_options.add_argument('--headless')
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')
    chrome_options.add_argument('--disable-gpu')
    chrome_options.add_argument('--window-size=1920,1080')
    chrome_options.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
    chrome_options.add_argument('--disable-blink-features=AutomationControlled')
    chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
    chrome_options.add_experimental_option('useAutomationExtension', False)
    
    service = Service(ChromeDriverManager().install())
    driver = webdriver.Chrome(service=service, options=chrome_options)
    driver.execute_cdp_cmd('Network.setUserAgentOverride', {"userAgent": 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'})
    driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    return driver

def get_stock_returns(driver, exchange, ticker, columns):
    url = f"https://www.morningstar.com/stocks/{exchange}/{ticker}/trailing-returns"
    print(f"Fetching data for {exchange}:{ticker}")
    print(url)
    
    try:
        driver.get(url)
        time.sleep(5)  # Wait for initial page load
        
        # Try to find any table on the page
        try:
            wait = WebDriverWait(driver, 10)  # Reduced timeout to 10 seconds
            wait.until(lambda d: len(d.find_elements(By.TAG_NAME, "table")) > 0)
        except TimeoutException:
            print(f"Timeout waiting for table for {exchange}:{ticker}")
            return None
            
        # Get the page source after JavaScript has loaded
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        tables = soup.find_all('table')
        
        if not tables:
            print(f"No tables found for {exchange}:{ticker}")
            return None
            
        table = tables[0]  # Get the first table
        
        returns = {}
        rows = table.find_all('tr')[1:]  # Skip header row
        
        # Get the second row (Industry)
        if len(rows) >= 2:
            row = rows[0]
            cols = row.find_all('td')
            if len(cols) >= 2:
                # Get all values except the first column (which is "Industry")
                for i, col in enumerate(cols[1:], 1):
                    value = col.text.strip().replace('%', '')
                    try:
                        returns[columns[i+1]] = float(value)  # i+1 because we skip Exchange and Ticker
                    except ValueError:
                        returns[columns[i+1]] = None
        else:
            print(f"Not enough rows found for {exchange}:{ticker}")
            return None
        
        print(returns)
        
        return returns if returns else None
        
    except Exception as e:
        print(f"Error processing {exchange}:{ticker}: {str(e)}")
        return None

def main():
    driver = setup_driver()
    
    try:
        tickers = read_stock_tickers('priv/morningstar_ticker.txt')
        columns = ['Exchange', 'Ticker', '1-Day', '1-Week', '1-Month', '3-Month', 'YTD', 
                  '1-Year', '3-Year', '5-Year', '10-Year', '15-Year']
        results = []
        
        for exchange, ticker in tqdm(tickers, desc="Processing stocks"):
            returns = get_stock_returns(driver, exchange, ticker, columns)
            if returns:
                row = [exchange, ticker]
                for period in columns[2:]:
                    row.append(returns.get(period, None))
                results.append(row)
                print(f"Added data for {exchange}:{ticker}")
            # time.sleep(random.uniform(3, 5))

        if not results:
            print("No data was collected!")
            return
            
        print(f"Total records collected: {len(results)}")
        df = pd.DataFrame(results, columns=columns)
        print("DataFrame created successfully")
        print(df.head())  # Print first few rows to verify data
        
        try:
            df.to_excel('stock_return.xlsx', index=False)
            print(f"Data successfully saved to stock_return.xlsx")
        except Exception as e:
            print(f"Error saving to Excel: {str(e)}")
            # Try saving as CSV as backup
            try:
                df.to_csv('stock_return.csv', index=False)
                print("Data saved to stock_return.csv as backup")
            except Exception as e:
                print(f"Error saving to CSV: {str(e)}")
    
    except Exception as e:
        print(f"Error in main process: {str(e)}")
    finally:
        driver.quit()

if __name__ == "__main__":
    main() 