# ENG2040 Assignment 1

Read `assignment_01_brief.pdf` for the task, assessment criteria, data notes and expected outputs.

## Set up the database

1. Extract this package and install Python 3.10 or later if needed. No additional Python packages or database server are required.
2. Open a terminal in the extracted folder and run:

   ```sh
   python3 setup_db.py
   ```

3. Open the resulting `marketplace.sqlite` with a SQLite client or from your own code.

The script imports `data/raw.sql` without cleaning it. It will not overwrite an existing database. To use another destination, run `python3 setup_db.py --db another_name.sqlite`.

The SQL file is the supplied dataset. The database is your local working copy. Keep the original SQL file unchanged. Submit the output data from every pipeline step in formats of your choice, as described in the assignment sheet.
