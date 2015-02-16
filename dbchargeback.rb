#
# Description: Creating custom chargeback report based on db usage sql extract.
#
$evm.log("info", "dbchargeback Automate Method Started ****************************")

@debug = true

require 'pg'
conn = PGconn.connect(:dbname=>'vmdb_production')

# Reading db names listed in sql report file: /var/www/miq/vmdb/db_usage
listed_dbnames = ""
for line in File.readlines("db_usage")
  db = line.split[0..0].join
  next if line =~ /^#/ or line =~ /^$/ or listed_dbnames.include? "#{db}\n"
  listed_dbnames += "#{db}\n"
end
$evm.log("info", "listed_dbnames: #{listed_dbnames}") if @debug

# Select only those dbnames chosen in service dialog: dialog_<dbname> attribute has "t" value
selected_dbnames = ""
for k, v in $evm.root.attributes
  db = k[7..100].to_s.strip
  next unless k =~ /^dialog_/ and v =~ /^t$/ and listed_dbnames.include? "#{db}\n" 
  selected_dbnames += "#{db}\n"
end
$evm.log("info", "selected_dbnames: #{selected_dbnames}") if @debug

# Going through each dbname and updating the most recent chargeback reports
for db in selected_dbnames.each_line
  report_name = "db-#{db.strip!}-chargeback-report"
	$evm.log("info", "Custom Report ID: #{report_name}")

	# Look for the custom report by name
	report_id = conn.exec("select id from miq_reports where name like \'#{report_name}\';")[0]["id"]
	$evm.log("info", "Custom Report ID: #{report_id}") if @debug

	# Look for the most recent instance of saved report
	result_id = conn.exec("select id from miq_report_results where miq_report_id=\'#{report_id}\' order by id desc limit 1;")[0]["id"]
	$evm.log("info", "Report Result ID: #{result_id}") if @debug

  # Getting saved report details data
    totals = 0
    lastrow_id = nil
	result_details = conn.exec("select * from miq_report_result_details where miq_report_result_id=\'#{result_id}\';")
	for d in result_details 
      line = d['data']
      allrows = line if line.include? "All Rows"
      totals = line.gsub(/.*\$/,"").gsub(/..td...tr.$/,"").gsub(/\,/,"").gsub(/\.[0-9][0-9]*/,"").to_i if line.include? "Totals:"
      lastrow_id = d['id']
      #$evm.log("info", "Line: #{d}\n")    
    end
  $evm.log("info", "All Rows: #{allrows}\n")	if @debug
  $evm.log("info", "Report Totals: #{totals}\n")	if @debug
  $evm.log("info", "Report LastRow_ID: #{lastrow_id}\n")	if @debug
  
  #Reading sql report file to calculate total of usage for given db
  totalusage = 0
  for line in File.readlines("db_usage")
    next if line =~ /^#/ or line =~ /^$/
    dbname = line.split[0..0].join
    if dbname == db
      user = line.split[1..1].join
      usage = line.split[3..3].join
      totalusage += usage.to_i
      $evm.log("info", "dbname: #{dbname} user: #{user} usage: #{usage} totalusage: #{totalusage}") if @debug
    end
  end

  #Reading sql report file to calculate amount for each user, for given db
  breakdown = "Total (breakdown by user): "
  for line in File.readlines("db_usage")
    amount = 0
    usage = 0
    next if line =~ /^#/ or line =~ /^$/
    dbname = line.split[0..0].join
    if dbname == db
      user = line.split[1..1].join
      usage = line.split[3..3].join
      amount = totals.to_i * usage.to_i / totalusage.to_i
      breakdown += " &nbsp;&nbsp;#{user}: $#{amount}<br>"
      $evm.log("info", "dbname: #{dbname} user: #{user} usage: #{usage} totalusage: #{totalusage} amount: #{amount} totals: #{totals}") if @debug
    end
  end
  $evm.log("info", "breakdown: #{breakdown}")
  
  #Creating new "Totals:" line
  newtotals = allrows.gsub(/All Rows/,"#{breakdown}").gsub(/\'/,"").gsub(/<td/,"<td align=right")
  $evm.log("info", "newtotals: #{newtotals}") if @debug

  #Update the last line in the report with the new totals
  result_id = conn.exec("update miq_report_result_details set data=\'#{newtotals}\' where id=\'#{lastrow_id}\';")
  $evm.log("info", "sql result: #{result_id}") if @debug

end
