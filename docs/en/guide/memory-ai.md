# Memory Book — AI Capabilities

The Memory Book is used to find information from saved daily, weekly, and monthly notes and generate answers based on the retrieved content. It consists of three stages: local search, record reading, and AI answer generation, each with its own responsibilities.

## Keyword Search

The Memory Book can search all records by keyword, or limit the search to daily, weekly, or monthly notes only. Keyword search returns matching documents along with their type, name, and preview information for locating potentially relevant records.

Keyword search requires at least two characters; multiple keywords match if any keyword hits. Search results are limited by the retrieval settings for count and context length. Search results are not full documents; matched records need to be read further to obtain the complete Markdown content.

## Time-Based Reading

When a question contains an explicit date or time period, the Memory Book can read the corresponding records directly:

- Read a daily note by calendar date;
- Read a weekly note by ISO year and week number;
- Read a monthly note by calendar year and month;
- Read a collection of weekly notes overlapping a specified month's date range.

Reading returns the full Markdown content of the target records. Weekly notes within a month are determined by date range; a week with any day falling in the target month may be included in the results, so a cross-month week may appear in queries for two adjacent calendar months.

## AI Answer

The Memory Book typically first determines whether the question contains clear date, week, or month clues, then decides whether to directly read records or perform keyword search. After obtaining relevant documents, the system passes the search results or complete records as answer context to the selected model, which then summarizes, compares, extracts, and explains.

AI answers only use locally retrieved or read content as factual basis. When no relevant historical Markdown is found, the answer cannot obtain corresponding local facts; the model can still organize language, but a new historical record is not created due to the absence of local records.

## Data Boundaries

The Memory Book's search and reading do not modify daily, weekly, or monthly notes. AI-generated answers, thinking content, and tool processes belong to the Memory Book session and are not automatically written back to note files. Markdown content only changes when edited and saved in the notebook.

When no Memory Book model is configured, local keyword search and record reading still work — matched records and full Markdown content can be viewed — but AI analysis, summaries, or follow-up answers are not generated. Provider connection failures, model incompatibility with the current request, or cancelled requests only affect the current answer; existing search results, local documents, and conversation history are not modified.
