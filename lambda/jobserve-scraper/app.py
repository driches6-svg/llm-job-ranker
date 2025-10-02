import json
import requests
from bs4 import BeautifulSoup
import html

def extract_job_ids_from_page(shid: str) -> list[str]:
    url = f"https://jobserve.com/gb/en/JobSearch.aspx?shid={shid}"
    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(url, headers=headers)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "lxml")
    job_ids_input = soup.select_one("input#jobIDs")
    if not job_ids_input:
        raise RuntimeError("Could not find jobIDs input field.")
    return job_ids_input.get("value", "").strip().split("#")

def get_full_job_details(job_id: str) -> dict:
    url = "https://jobserve.com/WebServices/JobSearch.asmx/RetrieveSingleJobDetail"
    headers = {
        "Content-Type": "application/json; charset=UTF-8",
        "Origin": "https://jobserve.com",
        "Referer": f"https://jobserve.com/gb/en/JobSearch.aspx?jid={job_id}",
        "User-Agent": "Mozilla/5.0"
    }
    resp = requests.post(url, headers=headers, json={"id": job_id})
    resp.raise_for_status()

    html_data = html.unescape(resp.json()["d"]["JobDetailHtml"])
    soup = BeautifulSoup(html_data, "lxml")

    return {
        "id": job_id,
        "title": soup.select_one("h1.positiontitle").get_text(strip=True) if soup.select_one("h1.positiontitle") else None,
        "location": soup.select_one("#md_location").get_text(strip=True) if soup.select_one("#md_location") else None,
        "rate": soup.select_one("#md_rate").get_text(strip=True) if soup.select_one("#md_rate") else None,
        "duration": soup.select_one("#md_duration").get_text(strip=True) if soup.select_one("#md_duration") else None,
        "agency": soup.select_one("#md_recruiter").get_text(strip=True) if soup.select_one("#md_recruiter") else None,
        "posted_date": soup.select_one("#md_posted_date").get_text(strip=True) if soup.select_one("#md_posted_date") else None,
        "reference": soup.select_one("#md_ref").get_text(strip=True) if soup.select_one("#md_ref") else None,
        "permalink": soup.select_one("#md_permalink").get("href") if soup.select_one("#md_permalink") else None,
        "description": soup.select_one(".main_detail_content").get_text(strip=True) if soup.select_one(".main_detail_content") else None,
    }

def lambda_handler(event, context):
    shid = event.get("shid", "8B48E22B1865559DA4EB")  # default SHID
    job_ids = extract_job_ids_from_page(shid)
    job_details = [get_full_job_details(job_id) for job_id in job_ids]
    return {
        "statusCode": 200,
        "body": json.dumps(job_details, indent=2)
    }