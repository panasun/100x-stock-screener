import pandas as pd
from bs4 import BeautifulSoup
import concurrent.futures
import time
from typing import Dict, List, Any, Optional
import os
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager

class GuruFocusScrape:
    def __init__(self):
        self.headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
        }
        self.file_name = "us_stock"
        self.cache = {}  # Simple in-memory cache to replace DB functionality
        self.initialize_driver()

    def initialize_driver(self):
        # Initialize Chrome options
        chrome_options = Options()
        chrome_options.add_argument('--headless')  # Run in headless mode
        chrome_options.add_argument('--no-sandbox')
        chrome_options.add_argument('--disable-dev-shm-usage')
        chrome_options.add_argument('--incognito')  # Add incognito mode
        chrome_options.add_argument(f'user-agent={self.headers["User-Agent"]}')
        
        # Initialize Chrome driver
        self.driver = webdriver.Chrome(
            service=Service(ChromeDriverManager().install()),
            options=chrome_options
        )
        self.wait = WebDriverWait(self.driver, 20)  # 20 seconds timeout

    def reset_driver(self):
        if hasattr(self, 'driver'):
            self.driver.quit()
        self.initialize_driver()

    def get_tickers(self) -> List[str]:
        try:
            with open(f"priv/{self.file_name}.txt", "r") as f:
                content = f.read()
                return [ticker.strip() for ticker in content.splitlines() if ticker.strip()]
        except Exception as e:
            print(f"Error reading tickers: {e}")
            return []

    def fetch_stock(self, ticker: str) -> Optional[str]:
        try:
            ticker = ticker.strip()
            url = f"https://www.gurufocus.com/stock/{ticker}/summary"
            
            # Use Selenium to fetch the page
            self.driver.get(url)
            
            # Wait for the main content to load
            self.wait.until(EC.presence_of_element_located((By.CLASS_NAME, "stock-indicators-table-row")))
            
            # Get the page source after JavaScript has loaded
            html = self.driver.page_source
            print(f"fetch_stock: {ticker}")
            self.cache[f"stock_{ticker}_summary_html"] = html
            return html
        except Exception as e:
            print(f"Error fetching stock {ticker}: {e}")
            return None

    def fetch_stocks(self):
        tickers = self.get_tickers()
        batch_size = 5  # Process 5 stocks at a time
        results = []  # Collect all results
        
        for i in range(0, len(tickers), batch_size):
            batch = tickers[i:i + batch_size]
            print(f"Processing batch: {batch}")
            
            # Process each stock in the batch
            for ticker in batch:
                print(f"Processing data for {ticker}")
                html = self.fetch_stock(ticker)
                if html:
                    summary_data = self.parse_summary_data(ticker)
                    if summary_data:
                        result = self.stock_screen(ticker)
                        if result:
                            results.append(result)
            
            # Reset driver after each batch
            print("Resetting browser for next batch...")
            self.reset_driver()
            
            # Optional: Add a small delay between batches
            time.sleep(2)
        
        # Write results to Excel after processing all stocks
        if results:
            df = pd.DataFrame(results)
            df.to_excel(f"data_{self.file_name}.xlsx", index=False)
            print(f"Successfully wrote {len(results)} stocks to data_{self.file_name}.xlsx")
        else:
            print("No results to write to Excel")

    def clean_title(self, title: str) -> str:
        if not title:
            return ""
        return (title.replace("\n", "")
                .replace("-", "_")
                .replace("(", " ")
                .replace(")", "")
                .replace("%", "")
                .replace("$", "")
                .replace("  ", " ")
                .strip()
                .replace(" ", "_")
                .lower())

    def parse_summary_data(self, ticker: str) -> Dict[str, Any]:
        html = self.cache.get(f"stock_{ticker}_summary_html")
        if not html:
            return {}

        soup = BeautifulSoup(html, 'html.parser')
        data = {"ticker": ticker}

        # Parse stock indicators table
        for row in soup.select(".stock-indicators-table-row"):
            cells = row.find_all("td")
            if len(cells) >= 3:
                key = self.clean_title(cells[1].text)
                value = cells[2].text.strip()
                data[key] = value

        # Parse t-caption table
        for row in soup.select(".t-caption"):
            cells = row.find_all("td")
            if len(cells) >= 3:
                key = self.clean_title(cells[1].text)
                value = cells[2].text.strip()
                if key:
                    data[key] = value

        # Parse GF Value
        gf_value = soup.select_one("a.color-primary span.t-primary")
        if gf_value:
            data["gf_value"] = gf_value.text.replace("$", "")

        # Parse Price
        price = soup.select_one("div.m-t-xs span.t-body-lg")
        if price:
            data["price"] = price.text.strip().replace("$", "").strip()

        self.cache[f"stock_{ticker}_summary"] = data
        print(data)
        return data

    def parse_number(self, value: Any) -> float:
        if value is None or value == "":
            return 0
        try:
            return float(str(value).replace(",", ""))
        except ValueError:
            return 0

    def ps_valuation(self, growth_rate: float, net_margin: float, ps_ratio: float) -> float:
        if ps_ratio == 0:
            return 0
        return round(((net_margin / 100 * 1 * (1 + growth_rate / 100) / ps_ratio + growth_rate / 100) * 100), 2)

    def stock_screen(self, ticker: str) -> Dict[str, Any]:
        stock = self.cache.get(f"stock_{ticker}_summary", {})
        print(f"stock_screen: {ticker}")

        data = {
            "0_ticker": ticker,
            "3_year_revenue_growth_rate": self.parse_number(stock.get("3_year_revenue_growth_rate")),
            "3_year_fcf_growth_rate": self.parse_number(stock.get("3_year_fcf_growth_rate")),
            "future_3_5y_total_revenue_growth_rate": self.parse_number(stock.get("future_3_5y_total_revenue_growth_rate")),
            "gross_margin": self.parse_number(stock.get("gross_margin")),
            "net_margin": self.parse_number(stock.get("net_margin")),
            "fcf_margin": self.parse_number(stock.get("fcf_margin")),
            "roe": self.parse_number(stock.get("roe")),
            "roa": self.parse_number(stock.get("roa")),
            "roic": self.parse_number(stock.get("roic")),
            "years_of_profitability_over_past_10_year": self.parse_number(stock.get("years_of_profitability_over_past_10_year")),
            "pe_ratio": self.parse_number(stock.get("pe_ratio")),
            "forward_pe_ratio": self.parse_number(stock.get("forward_pe_ratio")),
            "peg_ratio": self.parse_number(stock.get("peg_ratio")),
            "ps_ratio": self.parse_number(stock.get("ps_ratio")),
            "price_to_free_cash_flow": self.parse_number(stock.get("price_to_free_cash_flow")),
            "price_to_operating_cash_flow": self.parse_number(stock.get("price_to_operating_cash_flow")),
            "ev_to_revenue": self.parse_number(stock.get("ev_to_revenue")),
            "ev_to_fcf": self.parse_number(stock.get("ev_to_fcf")),
            "ev_to_ebitda": self.parse_number(stock.get("ev_to_ebitda")),
            "revenue_ttm_mil": self.parse_number(stock.get("revenue_ttm_mil")),
            "cash_to_debt": self.parse_number(stock.get("cash_to_debt")),
            "debt_to_equity": self.parse_number(stock.get("debt_to_equity")),
            "altman_z_score": self.parse_number(stock.get("altman_z_score")),
            "beneish_m_score": self.parse_number(stock.get("beneish_m_score")),
            "price": self.parse_number(stock.get("price")),
            "gf_value": self.parse_number(stock.get("gf_value"))
        }

        # Calculate valuations
        valuation = {
            "rule_of_40": data["net_margin"] + data["3_year_revenue_growth_rate"],
            "rule_of_40_fcf": data["fcf_margin"] + data["3_year_revenue_growth_rate"],
            "exp_return_ps_3_year_revenue_growth_net_margin": 
                self.ps_valuation(data["3_year_revenue_growth_rate"], data["net_margin"], data["ps_ratio"]),
            "exp_return_ps_3_year_fcf_growth_net_margin":
                self.ps_valuation(data["3_year_fcf_growth_rate"], data["net_margin"], data["ps_ratio"]),
            "exp_return_ps_future_3_5_year_revenue_growth_net_margin":
                self.ps_valuation(data["future_3_5y_total_revenue_growth_rate"], data["net_margin"], data["ps_ratio"]),
            "exp_return_ps_3_year_revenue_growth_fcf_margin":
                self.ps_valuation(data["3_year_revenue_growth_rate"], data["fcf_margin"], data["ps_ratio"]),
            "exp_return_ps_3_year_fcf_growth_fcf_margin":
                self.ps_valuation(data["3_year_fcf_growth_rate"], data["fcf_margin"], data["ps_ratio"]),
            "exp_return_ps_future_3_5_year_revenue_growth_fcf_margin":
                self.ps_valuation(data["future_3_5y_total_revenue_growth_rate"], data["fcf_margin"], data["ps_ratio"]),
            "gf_ratio": data["price"] / data["gf_value"] if data["gf_value"] > 0 and data["price"] > 0 else None
        }

        return {**data, **valuation}

    def run_stock_screen(self):
        tickers = self.get_tickers()
        results = []
        
        for ticker in tickers:
            result = self.stock_screen(ticker)
            if result:
                results.append(result)

        # Write to Excel
        df = pd.DataFrame(results)
        df.to_excel(f"data_{self.file_name}.xlsx", index=False)
        return results

def main():
    scraper = GuruFocusScrape()
    scraper.fetch_stocks()  # This will now automatically process the data and write to Excel
    # No need to call run_stock_screen separately as it's handled in fetch_stocks

if __name__ == "__main__":
    main() 