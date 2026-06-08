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
- After checking this for each result from ground truth, you should save the result as a .csv in generated/metrics/{name of subfolder from where you took predicted results, like yaml_short + model name}.csv.


# generation


I want you to add code to @src/generation_metrics.py that will do the following:
- it should take paths to generation_metrics_paths. It should also take a string, that should be deleted from the end of each file path, if the filename ends with this.
- Then it should combine all datasets into one,  as columns we should have all possible labels from @src/generation_metrics.py like 'No matching values', 'Not generated' and so on. As index - difficulty, then model name (parsed from path), then comment style (parsed from path), then description style. As values - counts (values from initial .csv files)
- Then you should save the result in processed/{database_name}/metrics/combined_search_top_k.xlsx, if special
parameter called source_column was passed (not None) then as combined_search_top_k_{source_column}.xlsx. 

Then I want you to add to file @src/plots.py a code, that will take a path to this combined metrics file and make a plot, it should also take style of comment and description as params and plot only those (actually you can make it into a list of tuples, each should have each own plot). The result should consist of 3 subplots in rows for each difficulty level, all the models should be present on one plot. It should be a bar plot, where we should have label like 'Everything matches' and then we have each models bar with their names at top (close to each other), then some distance and then next label and so on. Labels should always go in the same order. Use all labels. Some models for some labels may have 0 values, it okay, still plot them. The result should be saved in processed/{database_name}/plots/combined_search_top_k.png. (Use the same name as from the passed throug param)

Also add the cells to notebook 4_generation_evaluation.ipynb that will call each of these functions.
If you have any question - ask them please.


# search

I want you to add code to @src/search_metrics.py that will do the following:
- it should take paths to metrics_paths, and mode for column it can be either 'combined', then it should use rows with column 'combined', or 'respective' then it should parse the type from the name of the file (like technical) and then for this file use 'predicted_technical' and so on.
- then it should combine all datasets into one. As index use combination of description and comment style parsed from the name of each file. Then save the result in processed/{database_name}/combined_search_top_k_{combined/respective}.xlsx



Then update @plots.py, so that it have a function that will receive a path to the combined file, load it and make 3 subplots (for each metric), it should be just a barplot that will use as a height value of the metric and as a name of the column style + description. Then save the result with the same name in processed/{database_name}/plots/combined_search_top_k_{combined/respective}.png ( Use the same name as from the passed throug param)

Also add the cells to notebook 3_search_evaluation.ipynb that will call each of these functions.
If you have any questions - ask them please.
