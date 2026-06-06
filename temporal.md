Now, we need to measure the quality of the search method in our vanna client class, for that we need to do the following:
- In file @src/search_metrics.py we need to create functions to compute ranking metrics, such as: mean reciprocal rank, mean average precision at k, mean recall at k.
- We need to measure search quality for different types of query descriptions (short, business, technical) separately. For that I propose the following approach.
    1. We need to delete existing collections in qdrant (we can pass this as a parameter to our pipeline function)
    2. We create a Vanna Client instance that will instantiate collections (since we deleted them in the previous step)
    3. We need to populate our collection with a list of DDL descriptions using render_table_ddls function and client.add_ddl method 
    4. We need to populate our collection with pairs of query description of a chosen type and SQL-scripts. Since not every row in our .csv file with query descriptions and related descriptions have a generated SQL-script, we need to start with checking for existence of the script in scripts folder using UUID. After leaving only rows that have respecting sql scripts, we need to leave only unique sets of query UUID, query description and respecting SQL. Then we need to ingest them into our qdrant vector store and not to forget to save UUID which are returned by the methon add_question_sql, we will use this UUID as a true label for our search. 
    5. As a result we will save a file in search subfolder as .csv file, it will be the same as *_rewritten_related.csv but will contain a true UUID of the query saved in qdrant.
    6. Then we will perform vector search using chosen k neighbours (n_results) in function get_similar_question_sql on each row that have a true label and each of related_*_query columns. We will get a list of results, parse UUID's in returned order and add them as another column separated by semicolon. So each of related_*_query columns will have it's own list of top_k returned uuids.
    7. Thus we will end up with potentially three files for now (depends on chosen params, but three if we pass as argument ['short', 'business', 'technical']). Each will have 1 + number of given modes additional columns: one for true UUID, and one for each of returned top k results. Also when saving a file, use as a name something simple, like business_top_5.csv. And note that the new columns also need to have meaningfull names.
    8. Then we will need a completely another function, that will take the paths to files from the previous step. And compute ranking metrics for each of the additional columns (find them by pattern of the name, like 'predicted_business') and for all of them combined (if they were one column). Save the result in search folder, like 'ranking_metrics_business.csv'
- Add a cell in 2_generate_scripts_and_queries.ipynb, that will first call a pipeline function that will populate the db, perform search, save result uuids, etc. Then based on returned paths call another function that will calculate metrics and save them as files. Then in another cell load_csv those files and print them.


Now, we need to measure the quality of generation of our Vanna client, for that I propose the following approach (use file @src/generation_metrics.py):
1. The quality should be measured using different styles of ddls comments, like ['inline', 'yaml'] and styles ['short', 'business', 'technical']. So we have 6 different combinations of DDL descriptions. These should be all passed as params and ddl's should be generated inside the pipeline.
2. We need to delete existing collections in qdrant (we can pass this as a parameter to our pipeline function)
3. We create a Vanna Client instance that will instantiate collections (since we deleted them in the previous step)
4. We need to populate our collection with a list of DDL descriptions using render_table_ddls function and client.add_ddl method.
5. We need to populate our collection with pairs of query description of a chosen type and SQL-scripts. Since not every row in our .csv file with query descriptions and related descriptions have a generated SQL-script, we need to start with checking for existence of the script in scripts folder using UUID. After leaving only rows that have respecting sql scripts, we need to leave only unique sets of query UUID, query description and respecting SQL. Note: for query description you should use either the passed source collumn, if it's not passed, find a corresponding 'query_{style}' (like query_technical) column. After that we should end up with unique rows of UUID, query, difficulty.
6. Create if needed folders named 'prediction_scripts' and 'prediction_results' and inside them create if needed a subfolder signifying a comment style like 'yaml_short' 
7. We need to perform k-fold cross validation stratified by difficulty. Use train part to populate our qdrant database using add_question_sql. Then for each query from test, use vanna_client.generate(query). Save the generated sql inside 'generation/prediction_scripts/{comment_style_subfolder}' using as name '{uuid}.txt'. Try to execute it, if it executes and returns something, sort by collumn names and values and (look at script_generator.py) save this dataframe as '{uuid}.csv' in 'generation/predicted_results/{comment_style_subfolder}'.
8. Return a list of subfolders with results

Then we would need another function, that will do the following:
- Take a path to results and list of paths of predicted results and also a path to .csv with query descriptions 
- Iterate over each predicted result path
- For each result in ground truth results we load the dataset and then try to load corresponding file from predicted results folder and then assign it's a label based one the following logic:
   * 'Not generated' - if there isn't a corresponding .csv file in predicted folder
   * 'Not matching number of rows and cols' - if both number of cols and rows are different
   * 'Not matching number of rows' - if only number of rows is different
   * 'Not matching number of columns' - if only number of columns is different
   * 'Not matching values' - number of rows and columns are the same, but the values are different. To compare values you should convert each value into a string and compare strings.
   * 'Everything matches' - number of rows and columns are the same and values are the same as well.
- As the result you should have a .csv with columns 'uuid', 'difficulty', 'label' for all uuid that have an SQL.
- After checking this for each result from ground truth, you should save the result as a .csv in generated/metrics/{name of subfolder from where you took predicted results, like yaml_short}.csv.

