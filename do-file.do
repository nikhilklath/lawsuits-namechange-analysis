clear all 

import delimited "C:\Users\nikhi\Downloads\Coding\stata_task.csv"

***********************************************************************************

// label all variables needed

label var id "Unique ID for each company"
label var ipo_date "Date when this company went public (IPO)"
label var sector "Sector/industry that the company is classified in"
label var province "Province/state where the company is headquartered"
label var soe "State-owned enterprise"
label define x 1 "government owns a substantial percent of outstanding stocks" 0 "government does not own a substantial percent of outstanding stocks"
label values soe x
label var ren_date "Date when the company changes its name,  Missing values means the company has not renamed"
label var corebrand "Whether the core brand is kept unchanged after renaming"

encode corebrand, gen(core)
drop corebrand
rename core corebrand
label define y 2 "the core brand is unchanged" 2 "the core brand is changed"
label values corebrand y

forvalues i = 1990/2017{
	label var debt_ass`i' "Debt to asset ratio (percentage) in the year `i'"
	label var total_ass`i' "Total asset in `i'"
	label var total_rev`i' "Total revenue in `i'"
	label var opr_pro`i' "Operation profit in `i'"
}

label define z 1 "lawsuit is decided by a judge" 2 "petitioner and respondent solved it via pre court mediation and the lawsuit is cancelled"

forvalues i = 1/156{
	label var announce_date`i' "The public announcement date of lawsuit `i'"
	label var amount`i' "The monetary amount involved in lawsuit `i'; Missing value treated as 0"
	label var trial_subm_date`i' "The date when lawsuit `i' is submitted to a trial court"
	label var process`i' "How is lawsuit `i' finally resolved?"
	encode process`i', gen(pr`i')
	qui drop process`i'
	rename pr`i' process`i'
	label values process`i' z
	label var side`i' "Whether the company is a petitioner or respondent in lawsuit `i'"
}

*********************************************************************************************

/*
Companies that changed their name as group 1 
and companies that never changed their name as group 2.
*/

gen group1 = !missing(ren_date) // companies which have a rename date
gen group2 = missing(ren_date) // companies that do not have a rename date
gen ren_date1 = date(ren_date, "DM20Y") // convert to date format
format ren_date1 %td

gen ren_year = year(ren_date1) // find the year of renaming

encode id, gen(id_num)

* save the data
save "C:\Users\nikhi\Downloads\Coding\stata_task.dta", replace

****************************************************************************

/*
Match each company in group 1 with a company in the same province from group 2 with the closest assets in the last year before renaming.
This is done using one by one nearest matching, without replacements, and differences caused by sequential order of the matching are not considered. 
The results will give group 3 (the companies matched with group 1) and group 4 (the companies never matched.)
*/

// keep relevant variables
qui keep id_num province ren_year total_ass* group*

reshape long total_ass, i(id) j(year)
qui keep if (year == (ren_year - 1)) | (group2 == 1)

forvalues i = 1991/2017{
    
	preserve
	
	// we keep only the data for a particular year
	qui keep if year == `i'
	sort group2
	qui sum group1 
	local p = r(sum) // find number of firms in group 1
	mat D = J(`p', 6, 0) // create a matrix for saving the match data
	local count = 1 // counter for number of matches
	
	tempfile temp1
	qui save `temp1' // save this data temporarily to load within the next loop
	forvalues j = 1/`p'{
		use "`temp1'", clear
		qui keep if province == province[`j'] // we keep only data for a particular province in year i
		
		mkmat id_num total_ass if group1==1, mat(B) // generate matrix for all the firms in group 1, province j, year i
		mkmat id_num total_ass if group1==0, mat(C) // generate matrix for all the firms in group 2, province j, year i
		
		qui sum group1
		local q = r(sum) // number of firms in group 1, province j, year i
		
		qui sum group2
		local r = r(sum) // number of firms in group 2, province j, year i
		
		forvalues k = 1/`q'{
		    // for every firm in group 1, province j, year i
			
		    local flag1 = 0 // dummy to check if the firm has already been matched
		    forvalues m = 1/`count'{
			    // loop over the row-length of the matrix of matches
				
				if(D[`m',1] == B[`k',1]){
				    // check if the firm k is has been matched in year i
				    local flag1 = 1
					break
				}
			}
			if (`flag1' == 0){
			    // if the firm k has not been matched, let us find a match
				
				// to start with, let us match firm k with the firm in group2, year j that has highest total_ass
				qui sum total_ass if group1==0
				local match_asset = r(max) // saves the total asset of matched firm
				
				forvalues l = 1/`r'{
				    // find the id_num of firm with highest total_ass
				    if(`match_asset' == C[`l',2]){
					    local match = C[`l',1] // saves the id of matched firm
					}
				}
				
				local diff = abs(B[`k',2] - `match_asset') // find the difference between total asset of firm k and the asset of matched firm
				
				forvalues l = 1/`r'{
				    // loop over every firm in group2
					if (abs(B[`k',2] - C[`l',2]) <= `diff'){
					    // if the difference between total asset of firm k and firm l is less than the previous difference
						
						local flag2 = 0 // dummy to indicate if firm k has already been matched to another firm
						
						forvalues m = 1/`count'{
						    // loop over the row-length of the matrix of matched firms
							
							if(D[`m',2] == C[`l',1]){
							    // check if the firm l has been matched to another firm already
								local flag2 = 1
								break
							}
						}
						
						if (`flag2' == 0){
						    // if firm l has not already been matched to another firm
							// save the new difference
							local diff = abs(B[`k',2] - C[`l',2])
							local match = C[`l',1] // save the match id
							local match_asset = C[`l',2] // save the total asset of this firm k
						}
					}
				}
				// save the data for target and matched firm in a matrix
				mat D[`count',1] = B[`k',1] // target id
				mat D[`count',2] = `match' // match id
				mat D[`count',3] = province[`j'] // province
				mat D[`count',4] = B[`k',2]  // asset of target firm
				mat D[`count',5] = `match_asset' // asset of matched firm
				mat D[`count',6] = `i'
				local count = `count' + 1 // increase the counter
			}
		}
	}
	// just save the matrix D in the form of a dataset
	qui drop _all
	svmat D
	qui drop if D1==0
	qui save "C:\Users\nikhi\Downloads\Coding\match`i'.dta",replace
	restore
}

cd "C:\Users\nikhi\Downloads\Coding"
use match1991.dta, clear
forvalues i = 1992/2017{
	append using match`i'
}

rename D1 id_num
rename D2 match_id
rename D3 province
rename D4 id_num_asset
rename D5 match_asset
rename D6 year

merge 1:1 id_num using "C:\Users\nikhi\Downloads\Coding\stata_task.dta"
mkmat id_num match_id year if !missing(match_id) , mat(A)

// create the variable group3 and group4

gen group3 = 0
forvalues i=1/3306{
	forvalues j = 1/996{
		if(id_num[`i'] == A[`j',2]){
			qui replace group3 = 1 in `i'
			qui replace year = A[`j',3] in `i'
			break
		}
	}
}

gen group4 = group1 == 0 & group3 == 0

******************************************************************

// keep group 1 and group 3 for further analysis
qui keep if group1==1 | group3==1

gen debt_ass = 0
gen total_ass = 0
gen total_rev = 0
gen opr_pro = 0

local len = _N

// generate the debt_ass, total_ass, total_rev, opr_pro in the last year before renaming

forvalues i = 1/`len'{
    local year = year[`i']
	qui replace debt_ass = debt_ass`year' in `i'
	qui replace total_ass = total_ass`year' in `i'
	qui replace total_rev = total_rev`year' in `i'
	qui replace opr_pro = opr_pro`year' in `i'
}

**************************************************************************************

// Calculate the cumulative number of lawsuits and the monetary amount involved for each company before renaming
gen cases = 0
gen amount = 0
forvalues i = 1/`len'{
    local tot_cases = 0
	local tot_amt = 0
    forvalues j = 1/156{
	    
	    if(!missing(announce_date`j'[`i'])){
		    local tot_cases = `tot_cases' + 1
			
			if (!missing(amount`j'[`i'])){
			    local tot_amt = `tot_amt' + amount`j'[`i']
			}
		}
		else{
		    break
		}
	}
	replace cases = `tot_cases' in `i'
	replace amount = `tot_amt' in `i'
}
************************************************************************

gen log_cases = log(1+cases)
gen log_amount = log(1+amount)
gen log_assets = log(1+total_ass)
gen log_debt = log(1+debt_ass)
gen log_rev = log(1+total_rev)
gen log_pro = log(1+opr_pro)

gen case_date1 = date(announce_date1, "DM20Y")
format case_date1 %td
gen case_year1 = year(case_date1)

//  possible specification to test if companies are more likely to change their names when facing more lawsuits
probit group1 log_cases log_amount log_assets log_debt log_rev log_pro i.year i.province if (case_year1 < year | missing(case_year1))

