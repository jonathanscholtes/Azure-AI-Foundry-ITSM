# Prompt Examples — ServiceDeskAssistant

Sample prompts for testing the `ServiceDeskAssistant` Foundry agent in the playground or via the notebook.

The agent has access to two MCP tools backed by the Halo ITSM knowledge base:

| Tool | What it does |
|---|---|
| `KBArticle` | Search and list knowledge base articles by keyword |
| `KBArticle/{id}` | Retrieve the full text of a specific article by ID |

The agent is instructed to **only** answer from knowledge base content — it will not use general knowledge or training data.

---

## 🔐 Passwords & Login

```
How do I reset my corporate password?
```

```
A new employee needs a temporary password to log in for the first time. What are the steps?
```

```
I'm locked out of my account. What should I do?
```

---

## 💻 Hardware

```
We have a new employee starting Monday. What is the process for setting up a new laptop for them?
```

```
My laptop charger is damaged and I need a replacement. How do I request one?
```

```
How do I set up a new desktop workstation for an employee?
```

```
I want to upgrade the hardware components on my desktop. What is the process?
```

---

## 🖨️ Printing

```
How do I configure my printer to print double-sided by default?
```

```
There is a stuck job in the print queue that won't clear. How do I remove it?
```

```
The printer toner is empty on the HP LaserJet Pro. How do I replace the toner cartridge?
```

---

## 🏠 Working from Home & VPN

```
How do I set up VPN to work from home?
```

```
I'm working remotely and can't connect to the VPN. What are the troubleshooting steps?
```

---

## 🗓️ Leave & Employee Benefits

```
How do I submit a leave request using the ITSM portal?
```

```
My leave request is showing an error. How do I resolve it?
```

---

## ⚠️ Known Errors

```
I'm getting an incorrect date format error. How do I fix it?
```

---

## 📱 Software & Applications

```
How do I upgrade to the latest version of an application?
```

```
I need help with an Office 365 issue.
```

---

## 🔍 Article Retrieval by ID

Once an article is returned, you can ask for a specific article directly by its ID:

```
Show me knowledge base article 42.
```

```
Retrieve the full content of KB article 7.
```

---

## 🚫 Out-of-Scope Queries (Expected "Not Found" Responses)

These prompts test that the agent correctly refuses to answer from general knowledge when the topic is not in the knowledge base:

```
What is the capital of France?
```

```
Can you write me a Python script to sort a list?
```

```
What is the weather like today?
```

> **Expected agent response:** *"Unable to find in knowledge base."*  
> The agent will search the KB first, find no matching article, and refuse to answer from general knowledge — this is correct, grounded behaviour.

---

## 💡 Tips for the Workshop

- Start with a **natural language query** — the agent will call `KBArticle` to search, then `KBArticle/{id}` to fetch the full article
- The agent returns the **full verbatim article text** — it does not summarize
- If a search returns multiple results, ask the agent to retrieve a specific one by ID
- Try rephrasing a query if the first search returns no results (e.g., "password reset" vs "reset my password")
- Out-of-scope questions are a useful demo of **grounding** — the agent stays within the KB boundary
