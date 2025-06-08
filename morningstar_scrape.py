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
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
from queue import Queue
import os

# Global variables for thread safety
excel_lock = threading.Lock()
batch_size = 100  # Number of records to save in each batch
columns = ['Exchange', 'Ticker', '1-Day', '1-Week', '1-Month', '3-Month', 'YTD', 
           '1-Year', '3-Year', '5-Year', '10-Year', '15-Year']

def read_existing_tickers(file_path):
    """Read tickers that have already been fetched from stocks_return.csv"""
    existing = set()
    if not os.path.exists(file_path):
        return existing
    with open(file_path, 'r') as f:
        next(f, None)  # skip header
        for line in f:
            parts = line.strip().split(',')
            if len(parts) >= 2:
                existing.add((parts[0], parts[1]))
    return existing

def read_stock_tickers(file_path, fetched_file='stocks_return.csv'):
    """Read tickers from input file, skip those already fetched"""
    all_tickers = []
    with open(file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if line:
                parts = line.split(',')
                if len(parts) == 2:
                    exchange, ticker = parts
                    all_tickers.append((exchange, ticker))
    already_fetched = read_existing_tickers(fetched_file)
    # Filter out tickers that already exist in stocks_return.csv
    to_fetch = [t for t in all_tickers if t not in already_fetched]
    print(f"Total tickers: {len(all_tickers)}, Already fetched: {len(already_fetched)}, To fetch: {len(to_fetch)}")
    return to_fetch

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

def get_stock_returns(driver, exchange, ticker):
    url = f"https://www.morningstar.com/stocks/{exchange}/{ticker}/trailing-returns"
    print(f"Fetching data for {exchange}:{ticker}")
    
    try:
        driver.get(url)
        time.sleep(5)  # Wait for initial page load
        
        try:
            wait = WebDriverWait(driver, 10)
            wait.until(lambda d: len(d.find_elements(By.TAG_NAME, "table")) > 0)
        except TimeoutException:
            print(f"Timeout waiting for table for {exchange}:{ticker}")
            return None
            
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        tables = soup.find_all('table')
        
        if not tables:
            print(f"No tables found for {exchange}:{ticker}")
            return None
            
        table = tables[0]
        returns = {'ticker': ticker, 'exchange': exchange}
        rows = table.find_all('tr')[1:]
        
        if len(rows) >= 2:
            row = rows[0]
            cols = row.find_all('td')
            if len(cols) >= 2:
                for i, col in enumerate(cols[1:], 1):
                    value = col.text.strip().replace('%', '')
                    try:
                        returns[columns[i+1]] = float(value)
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

def save_to_file(row_data, is_first=False):
    """Save a single row of data to text file"""
    with excel_lock:
        try:
            # Convert row data to string format
            row_str = [str(val) if val is not None else '' for val in row_data]
            
            # Write to file
            with open('stocks_return.csv', 'a') as f:
                if is_first:
                    # Write header for first row
                    f.write(','.join(columns) + '\n')
                f.write(','.join(row_str) + '\n')
            
            return True
        except Exception as e:
            print(f"Error saving data: {str(e)}")
            return False

def process_ticker(ticker_data):
    """Process a single ticker and return the results"""
    exchange, ticker = ticker_data
    driver = setup_driver()
    try:
        returns = get_stock_returns(driver, exchange, ticker)
        if returns:
            row = [exchange, ticker]
            for period in columns[2:]:
                row.append(returns.get(period, None))
            # Save immediately after getting data
            save_to_file(row, is_first=not os.path.exists('stocks_return.csv'))
            return row
    except Exception as e:
        print(f"Error processing {exchange}:{ticker}: {str(e)}")
    finally:
        driver.quit()
    return None

def main():
    tickers = read_stock_tickers('priv/morningstar_ticker.txt', 'priv/stocks_return.csv')
    total_tickers = len(tickers)
    print(f"Total tickers to process: {total_tickers}")
    
    max_workers = 5
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_ticker, ticker): ticker for ticker in tickers}
        
        for future in tqdm(as_completed(futures), total=len(futures), desc="Processing stocks"):
            future.result()  # We don't need to store results anymore
    
    print("Processing completed!")

if __name__ == "__main__":
    main() 