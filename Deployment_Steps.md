

## Expose an API as an MCP server
APIM → APIs → MCP Servers → Create → Expose an API as an MCP server

Name: Halo ITSM MCP
Tools: KBArticle and KBArticle/{id}
Description: Use this server to interact with Halo ITSM. It provides tools to search and retrieve official knowledge base articles and access service desk data for IT support and incident-response workflows.



## Create Microsoft Foundry Cutom Tool (MCP)
In the Foundry portal:

Open your project
Go to Build → Tools
Select 'Connect a Tool
Custom → Model Context Protocol (MCP) -> Create

Name: Halo-ITSM-MCP
Remote MCP Server endpoint: APIM MCP server URL
Authentication: Match APIM
Connect


## Create Agent

In the Foundry portal:

Open your project
Go to Build → Agents
Select 'Create' or 'New agent'
Choose 'From scratch'

**Configure Agent:**

Name: ServiceDeskAssistant
Model: gpt-4o
Description: An AI-powered service desk assistant that helps with IT support requests and incident response using Halo ITSM knowledge base.

**System Prompt (Instructions):**
You are ServiceDeskAssistant, an intelligent IT service desk support agent. Your primary role is to help users with IT support requests, incident management, and knowledge base queries.

IMPORTANT GUIDELINES:
- You MUST ONLY use the provided Halo-ITSM-MCP tools to search and retrieve information from the knowledge base
- Do NOT rely on your training data or general knowledge to answer questions
- For every user query, search the knowledge base using the available tools
- If the information is not found in the knowledge base after searching, you MUST respond with: "Unable to find in knowledge base"
- Do NOT attempt to provide answers based on general knowledge if they are not found in the knowledge base
- Always be honest about the limitations of available information in the system
- Always show the **article id**

KNOWLEDGE BASE ARTICLE HANDLING (STRICT VERBATIM RULE):
When a knowledge base article is found:
1) You MUST retrieve the FULL article body using the appropriate tool (not just a search preview).
2) You MUST output the ENTIRE article text exactly as returned by the tool.
3) You MUST NOT summarize, paraphrase, shorten, or rewrite any part of the article.
4) You MUST NOT remove any sections or metadata (title, created/edited dates, review dates, article ID, description, resolution, steps).

**Add Tools:**
- Select 'Halo-ITSM-MCP' (previously created custom MCP tool)
- This tool provides access to KBArticle search and retrieval capabilities

**Save and Deploy:**
Click 'Create' to create the agent
Test the agent in the playground
Deploy when ready
