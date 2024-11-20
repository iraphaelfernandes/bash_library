#!/bin/bash


BOOKS_DB="books.csv"
MEMBERS_DB="members.csv"
LENDING_DB="lending.csv"


error() {
    echo "Error: $1"
}


success() {
    echo "Success: $1"
}


calculate_check_digit() {
    local isbn=$1
    local sum=0

    # Calculate sum of the first 12 ISBN digits with alternating weights of 1 and 3
    for (( i=0; i<12; i++ )); do
        digit=${isbn:i:1}
        if (( i % 2 == 0 )); then
            sum=$((sum + digit))       
        else
            sum=$((sum + digit * 3))
        fi
    done

    
    local check_digit=$((10 - sum % 10))
    if [ "$check_digit" -eq 10 ]; then
        check_digit=0
    fi

    echo "$check_digit"
}


# Main command interpreter
main() {
    while true; do
        echo -n "Enter command (quit, list, search, delete, update, suspend, resume, loan, return, reserve, report)"
        read -r command args

        case "$command" in
            "quit" | "exit")
                exit 0
                ;;
            "list")
                list_entries $args
                ;;
            "search")
                search_entries $args
                ;;
            "delete")
                delete_entry $args
                ;;
            "update")
                update_entry $args
                ;;
            "suspend")
                suspend_member $args
                ;;
            "resume")
               resume_member $args
                ;;
            "loan")
                loan_book $args
                ;;
            "return")
                return_book $args
                ;;
            "reserve")
                reserve_book $args
                ;;
            "report")
                report_late_books $args
                ;;
            *)
                error "Unknown command!"
                ;;
        esac
    done
}

# Function to list all books or members
list_entries() {
    local type=$1
    case "$type" in
        "books")
            
            awk -F, '$4 == "0"' $BOOKS_DB | sort -t, -k1,1 | column -s, -t
            ;;
        "members")
        
            awk -F, '$4 == "0"' $MEMBERS_DB | sort -t, -k2,2 | column -s, -t
            ;;
        *)
            error "Invalid list type: Use 'books' or 'members'"
            ;;
    esac
}


search_entries() {
    local type=$1
    local key=$2
    local file=""

    if [ "$type" = "books" ]; then
        file=$BOOKS_DB
        if [ -z "$key" ]; then
            # List all books if no search key provided
            list_entries books
            return
        fi
        
        result=$(awk -F, -v key="$key" '$2 ~ ("^" key) && $4 == "0" {print $0}' "$file" | sort -t, -k1,1)
        
    elif [ "$type" = "members" ]; then
        file=$MEMBERS_DB
        if [ -z "$key" ]; then
        
            list_entries members
            return
        fi
       
        result=$(awk -F, -v key="$key" '$2 ~ ("^" key) && $4 == "0" {print $0}' "$file" | sort -t, -k2,2)
        
    else
        error "Invalid search type. Use 'books' or 'members'"
        return
    fi

    
    if [ -n "$result" ]; then
        echo "$result" | column -s, -t
    else
        error "No entry found for '$key' in $type"
    fi
}




delete_entry() {
    local type=$1
    local key=$2
    local file=""
    local filter_column=""

    # Determine the file and column based on type
    if [ "$type" = "book" ]; then
        file=$BOOKS_DB
        filter_column=1 

        if ! grep -q "^$key," "$file"; then
            error "Book with ISBN $key not found"
            return
        fi
        
        if ! awk -F, -v key="$key" '$1 == key && $4 == "0"' "$file" | grep -q .; then
            error "Book already deleted"
            return
        elif grep -q "^$key,.*,0$" "$LENDING_DB"; then
            error "Cannot delete: Active loan exists for book $key"
            return
        fi
    elif [ "$type" = "member" ]; then
        file=$MEMBERS_DB
        filter_column=1 

        if ! grep -q "^$key," "$file"; then
            error "Member $key not found"
            return
        fi
        
        if ! awk -F, -v key="$key" '$1 == key && $4 == "0"' "$file" | grep -q .; then
            error "Member already deleted"
            return
        elif grep -q "^[^,],$key,.,0$" "$LENDING_DB"; then
            error "Cannot delete: Active loan exists for member $key"
            return
        fi
    else
        error "Invalid delete command. Use 'book' or 'member'"
        return
    fi

    # Mark the entry as deleted in the database
    awk -F, -v key="$key" -v col="$filter_column" 'BEGIN{OFS=FS} {if ($col == key) $4 = 1; print}' "$file" > tmp && mv tmp "$file"
    success "$type with key $key deleted"
}


# Function to update a book title or member name
update_entry() {
    local type=$1
    local isbn_or_id=$2
    shift 2  
    local title_or_name="$*"  

    if [ "$type" = "book" ]; then
        # Ensure ISBN is a 13-digit number
        if ! [[ $isbn_or_id =~ ^[0-9]{13}$ ]]; then
            error "Invalid ISBN format. ISBN must be a continuous 13-digit number"
            return
        fi

        # Calculate and validate the check digit
        local check_digit=$(calculate_check_digit "$isbn_or_id")
        if [ "${isbn_or_id:12:1}" -ne "$check_digit" ]; then
            error "Invalid ISBN: Check digit does not match"
            return
        fi

        # Check if the book exists and update or add it accordingly
        if grep -q "^$isbn_or_id," "$BOOKS_DB"; then
            # Update the title if the book exists
            awk -F, -v isbn="$isbn_or_id" -v title="$title_or_name" 'BEGIN {OFS=FS} {if ($1 == isbn) $2 = title; print}' "$BOOKS_DB" > tmp && mv tmp "$BOOKS_DB"
            success "Book with ISBN $isbn_or_id updated with title \"$title_or_name\""
        else
            
            echo "$isbn_or_id,\"$title_or_name\",,0" >> "$BOOKS_DB"
            success "New book added with ISBN $isbn_or_id and title \"$title_or_name\""
        fi

    elif [ "$type" = "member" ]; then
        # Check if the member exists and update or add it accordingly
        if grep -q "^$isbn_or_id," "$MEMBERS_DB"; then
            # Update the name if the member exists
            awk -F, -v id="$isbn_or_id" -v name="$title_or_name" 'BEGIN {OFS=FS} {if ($1 == id) $2 = name; print}' "$MEMBERS_DB" > tmp && mv tmp "$MEMBERS_DB"
            success "Member with ID $isbn_or_id updated with name \"$title_or_name\""
        else
            # Add new member entry if ID does not exist
            echo "$isbn_or_id,\"$title_or_name\",0,0" >> "$MEMBERS_DB"
            success "New member added with"
        fi
    else
        error "Invalid update type. Use 'book' or 'member'"
    fi
}


# Function to suspend a member
suspend_member() {
    local member_id=$1

    # Check if the database file exists
    if [ ! -f "$MEMBERS_DB" ]; then
        error "Database file $MEMBERS_DB not found"
        return
    fi

    # Check if the member exists in the database
    if grep -q "^$member_id," "$MEMBERS_DB"; then
        # Use awk to set the suspended status to 1 if it's currently 0
        awk -F, -v id="$member_id" 'BEGIN {OFS=FS} {if ($1 == id && $3 == 0) $3 = 1; print}' "$MEMBERS_DB" > tmp && mv tmp "$MEMBERS_DB"
        
        # Confirm if the suspension was successful by checking the updated file
        if grep -q "^$member_id,[^,]*,1," "$MEMBERS_DB"; then
            success "Member with ID $member_id has been suspended"
        else
            error "Member with ID $member_id is already suspended"
        fi
    else
        error "Member with ID $member_id not found in the database"
    fi
}

# Function to resume a member
resume_member() {
    local member_id=$1

    # Check if the database file exists
    if [ ! -f "$MEMBERS_DB" ]; then
        error "Database file $MEMBERS_DB not found"
        return
    fi

    
    if grep -q "^$member_id," "$MEMBERS_DB"; then
        
        awk -F, -v id="$member_id" 'BEGIN {OFS=FS} {if ($1 == id && $3 == 1) $3 = 0; print}' "$MEMBERS_DB" > tmp && mv tmp "$MEMBERS_DB"

        # Confirm if the resume operation was successful by checking the updated file
        if grep -q "^$member_id,[^,]*,0," "$MEMBERS_DB"; then
            success "Member with ID $member_id has been resumed"
        else
            error "Member with ID $member_id is already active"
        fi
    else
        error "Member with ID $member_id not found in the database"
    fi
}

# Function to loan a book to a member
loan_book() {
    local isbn=$1
    local member_id=$2

   
    if [ ! -f "$BOOKS_DB" ] || [ ! -f "$MEMBERS_DB" ] || [ ! -f "$LENDING_DB" ]; then
        error "One or more database files are missing."
        return
    fi

    # Check if the book exists, is available (deleted field is 0), and is not reserved by a different member
    local book_entry=$(grep "^$isbn," "$BOOKS_DB")
    if [ -z "$book_entry" ]; then
        error "Book with ISBN $isbn not found."
        return
    elif [[ $(echo "$book_entry" | cut -d',' -f4) -ne 0 ]]; then
        error "Book with ISBN $isbn is not available for loan."
        return
    elif [[ $(echo "$book_entry" | cut -d',' -f3) != "$member_id" && -n $(echo "$book_entry" | cut -d',' -f3) ]]; then
        error "Book with ISBN $isbn is reserved by a different member."
        return
    fi

    # Check if the book is already loaned out
    if grep -q "^$isbn,.*,.*0$" "$LENDING_DB"; then
        error "Book with ISBN $isbn is already loaned."
        return
    fi

    # Check if the member exists, is not deleted, and is not suspended
    local member_entry=$(grep "^$member_id," "$MEMBERS_DB")
    if [ -z "$member_entry" ]; then
        error "Member with ID $member_id not found."
        return
    elif [[ $(echo "$member_entry" | cut -d',' -f4) -eq 1 ]]; then
        error "Member with ID $member_id is marked as deleted."
        return
    elif [[ $(echo "$member_entry" | cut -d',' -f3) -eq 1 ]]; then
        error "Member with ID $member_id is suspended."
        return
    fi

    # Set the start date to the current date and the end date to 7 days later
    local start_date=$(date +%Y-%m-%d)
    local end_date=$(date -v+7d +%Y-%m-%d)  # Compatible with macOS

    # Add the loan entry to the lending database with the correct format
    echo "$isbn,$member_id,$start_date,$end_date,0" >> "$LENDING_DB"
    success "Book with ISBN $isbn has been loaned to member ID $member_id from $start_date to $end_date."

    # Clear the reservation if the book was reserved by this member
    if [[ $(echo "$book_entry" | cut -d',' -f3) == "$member_id" ]]; then
        # Clear the reservation in the books database by setting reserved_by to an empty string
        awk -F, -v isbn="$isbn" 'BEGIN {OFS=FS} {if ($1 == isbn) $3 = ""; print}' "$BOOKS_DB" > tmp && mv tmp "$BOOKS_DB"
        success "Reservation cleared for book with ISBN $isbn by member ID $member_id."
    fi
}

# Function to return a loaned book
return_book() {
    local isbn=$1

    # Check if the lending database file exists
    if [ ! -f "$LENDING_DB" ]; then
        error "Lending database file $LENDING_DB not found."
        return
    fi

    # Check if the book is currently on loan (returned field is 0)
    if grep -q "^$isbn,.,.,.*,0$" "$LENDING_DB"; then
        # Use awk to set the returned status to 1 for the matching loan entry
        awk -F, -v isbn="$isbn" 'BEGIN {OFS=FS} {if ($1 == isbn && $5 == 0) $5 = 1; print}' "$LENDING_DB" > tmp && mv tmp "$LENDING_DB"
        
        # Confirm the update by checking if the returned status has been set to 1
        if grep -q "^$isbn,.,.,.*,1$" "$LENDING_DB"; then
            success "Book with ISBN $isbn has been successfully returned."
        else
            error "Failed to update return status for book with ISBN $isbn."
        fi
    else
        error "No open loan found for book with ISBN $isbn."
    fi
}

# Function to reserve a book for a member
reserve_book() {
    local isbn=$1
    local member_id=$2

    # Check if the database files exist
    if [ ! -f "$BOOKS_DB" ] || [ ! -f "$MEMBERS_DB" ]; then
        error "One or more database files are missing."
        return
    fi

    # Check if the book exists, is available (deleted field is 0), and is not already reserved
    local book_entry=$(grep "^$isbn," "$BOOKS_DB")
    if [ -z "$book_entry" ]; then
        error "Book with ISBN $isbn not found."
        return
    elif [[ $(echo "$book_entry" | cut -d',' -f4) -ne 0 ]]; then
        error "Book with ISBN $isbn is not available for reservation (marked as deleted)."
        return
    elif [[ -n $(echo "$book_entry" | cut -d',' -f3) ]]; then
        error "Book with ISBN $isbn is already reserved."
        return
    fi

    # Check if the member exists, is not deleted, and is not suspended
    local member_entry=$(grep "^$member_id," "$MEMBERS_DB")
    if [ -z "$member_entry" ]; then
        error "Member with ID $member_id not found."
        return
    elif [[ $(echo "$member_entry" | cut -d',' -f4) -eq 1 ]]; then
        error "Member with ID $member_id is marked as deleted."
        return
    elif [[ $(echo "$member_entry" | cut -d',' -f3) -eq 1 ]]; then
        error "Member with ID $member_id is suspended."
        return
    fi

    
    awk -F, -v isbn="$isbn" -v member_id="$member_id" 'BEGIN {OFS=FS} {if ($1 == isbn) $3 = member_id; print}' "$BOOKS_DB" > tmp && mv tmp "$BOOKS_DB"
    success "Book with ISBN $isbn has been reserved by member ID $member_id."
}



report_late_books() {
    local days=${1:-0}
    local today=$(date +%Y-%m-%d)

    awk -F, -v days="$days" -v today="$today" '
    {
        if ($5 == "0") {
            diff = (systime() - mktime(gensub("-", " ", "g", $4)))/(60*60*24);
            if (diff > days) print $1, $2, $3, $4;
        }
    }' $LENDING_DB | column -t
}


main