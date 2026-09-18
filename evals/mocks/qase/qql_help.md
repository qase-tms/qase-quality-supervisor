---
expect:
  topic: [overview, syntax, entities, operators, functions, examples, aggregation, enumValues]
---

{"topic":"reference","content":{"entities":{"result":["status","run_id","case_id","comment","stacktrace","end_time","ended","is_api_result","time_spent_ms"],"case":["id","title","suite_id","automation","priority","is_flaky","created","updated"],"run":["id","title","status","started","ended","milestone_id","environment_id"],"defect":["id","title","severity","status","created"]},"aggregation":"SELECT (field, COUNT(*)) <filter> GROUP BY field","timestamps":{"result":"ended","case":"created/updated","run":"started/ended"},"enumValues":{"result.status":{"1":"Passed","2":"Failed","3":"Blocked","4":"Retest","5":"Skipped","7":"In progress","8":"Invalid"},"case.automation":{"0":"Manual","1":"To be automated","2":"Automated"},"case.priority":{"0":"Not set","1":"High","2":"Medium","3":"Low"}},"note":"Filters take labels (status = \"failed\"); GROUP BY returns the enum as an integer."}}
