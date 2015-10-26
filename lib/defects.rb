# get all the defects updated during release and check the revision history for each to:
#
# 1. figure out how wsi is changing on a weekly basis
# 2. get activity lists (who created, fixed, closed)
#

# sudo gem install rally_rest_api [ add to gem file ]

PROJECT_NAME=ENV["RALLY_PROJECT_NAME"]
RELEASE_NAME=ENV["RALLY_PROJECT_NAME"]

LOGIN=ENV["RALLY_LOGIN"]
PASSWORD=ENV["RALLY_PASSWORD"]

# compile regular expressions
# Scheduled User Story [US4345: Enhance System Health - Status & Message in  System Health  for VPM overloading]
SCHEDULED_RE=/Scheduled User Story \[(US[0-9\.]+)/
UNSCHEDULED_RE=/Unscheduled User Story \[(US[0-9\.]+)/

FIXED_RE=/STATE changed from \[[A-Za-z ]*\] to \[Fixed\]/
CLOSED_RE=/STATE changed from \[[A-Za-z ]*\] to \[Closed\]/


ENV['RAILS_ENV'] ||= 'development'

#require File.join(File.dirname(__FILE__),'..','config','environment')

#require 'rubygems'
require 'rally_rest_api'
require 'date'
require 'pp'

def incremental_average(previousAverage,value,nvalues)
   return(((value-previousAverage)/(nvalues+1))+previousAverage)
end

# convert a rally date to a ruby date
def get_date(rally_date_field)
   the_date=DateTime.parse(rally_date_field).to_date()
   #the_date=DateTime.new(date_arr[0],date_arr[1],date_arr[2])
   return(the_date)
end

def get_wsi(defect)
  
   if (defect.severity=="Low")
      return(1)
   elsif (defect.severity=="Medium")
      return(7)
   elsif (defect.severity=="High")
      return(20)
   end
   return(0)
end

def process_defects(defect_list,start_date,end_date,wsi_hash)
  
   total_created_defects=0
   total_fixed_defects=0
   total_closed_defects=0
   total_deferred=0
   wsi=0
  
   open_bucket=Hash.new
  
   closed_resolution_bucket=Hash.new
  
   # current state of defects
   current_open=0
   current_fixed=0
   current_cannotfix=0
   current_closed=0
   current_deferred=0
  
   high_priority=0
   high_severity=0
  
   defect_list.each do |defect|
  
      last_updated=get_date(defect.last_update_date)
      created_date=get_date(defect.creation_date)
      createdby=nil
      severity=get_wsi(defect)
     
      # 'created' calculations are only affected by defects created between the specified dates
      if (!created_date.nil? && created_date>=start_date && created_date<=end_date)
         
         total_created_defects=total_created_defects+1
        
         d=created_date
         
         # bucket data into weeks - using Monday as date
         d=Date.commercial(created_date.year,created_date.cweek,1)
         
         # use week number? (cweek) or julian date?
         
         record=wsi_hash[d]
         if (record)
            record[:created]=record[:created]+severity
         else
            wsi_hash[d]={ :created => severity, :fixed => 0, :closed => 0 }
         end
         
      end
     
      # puts "@@@@@@@@@@@@@@@ defect state==#{defect.state}"
      
      # counts for defect current state
      if (defect.state=="Fixed")
         current_fixed=current_fixed+1
      elsif (defect.state=="Cannot fix")
         current_cannotfix=current_cannotfix+1
      elsif (defect.state=="Closed")
         current_closed=current_closed+1
       
         if (closed_resolution_bucket[defect.resolution].nil?)
            closed_resolution_bucket[defect.resolution]=0
         end
         closed_resolution_bucket[defect.resolution]+=1
      elsif (defect.state=="Open" || defect.state=="Submitted")
         current_open=current_open+1
         if (defect.severity=="High")
            high_severity=high_severity+1
         end
         if (defect.priority=="High")
            high_priority=high_priority+1
         end
      elsif (defect.state=="Defer")
         current_deferred=current_deferred+1
      end
     
      fixed_date=nil
      thefixer=nil
     
      closed_date=nil
      closedby=nil
     
      defect.revision_history.revisions.each do |revision|
       
         if (revision.description=='Original revision')
            # already got creation date, check who created the defect
            createdby=revision.user
           
            # removed as I try to fix the wsi calculations
            #wsi=wsi+severity
           
         elsif (defect.state=="Fixed" || defect.state=="Closed")
            # check if this is X->Fixed transition
            m=FIXED_RE.match(revision.description)
            if (m)
               thefixer=revision.user
               #if ($fixed_statistics[thefixer].nil?)
               #   $fixed_statistics[thefixer]=Array.new();
               #end
               #$fixed_statistics[thefixer] << defect
              
               # get fixed date
               fixed_date=get_date(revision.creation_date)
               if (!fixed_date.nil? && fixed_date>=start_date && fixed_date<=end_date)
                  total_fixed_defects=total_fixed_defects+1
                 
                  # add to the wsi hash
                  #d=fixed_date.to_time.to_i*1000
                  d=fixed_date
                  
                  # bucket data into weeks
                  d=Date.commercial(fixed_date.year,fixed_date.cweek,1)
                  
                  record=wsi_hash[d]
                  if (record)
                     record[:fixed]=record[:fixed]+severity
                  else
                     wsi_hash[d]={ :created => 0, :fixed => severity, :closed => 0 }
                  end
                 
               end
            else
               # check if this is X->Closed transition
               m=CLOSED_RE.match(revision.description)
               if (m)
                  # get closed date
                  closedby=revision.user
                  closed_date=get_date(revision.creation_date)
                  if (!closed_date.nil? && closed_date>=start_date && closed_date<=end_date)
                     total_closed_defects=total_closed_defects+1
                     
                     # removed as I try to fix the wsi calculations
                     #wsi=wsi-severity
                    
                     if (!created_date.nil? && created_date>=start_date && created_date<=end_date)
                        # only counted if defect was created during project... TODO: count the stuff from previous projects that was fixed?
                        d=closed_date
                        
                        # bucket data into weeks
                        d=Date.commercial(closed_date.year,closed_date.cweek,1)
                        
                        record=wsi_hash[d]
                        if (record)
                           record[:closed]=record[:closed]+severity
                        else
                           wsi_hash[d]={ :created => 0, :fixed => 0, :closed => severity }
                        end
                     end
                  end
               end
            end
         elsif (defect.state=="Deferred")
            # TBD need to check if it was deferred during course of this release!!!
            
         end
      end
   end
  
   # figure out the daily cumulative wsi score
   # wsi increases when a defect is opened, and decreases when a defect is *closed* (NOT when it's fixed)
   wsi_daily=[]
   tmp=wsi_hash.to_a.sort
   xwsi=0
   tmp.each { |item|
      record=item[1]
      xwsi=xwsi+record[:created]-record[:closed]
      #wsi=wsi+record[:created]-record[:fixed]
      wsi_daily.push([item[0],xwsi])
    
      print "#{item[0].strftime('%Y-%m-%d')} CREATED=#{record[:created]} CLOSED=#{record[:closed]} FIXED=#{record[:fixed]} WSI=#{xwsi}\n"
   }
  
   print "\ntotal created in time period: ", total_created_defects, "\n"
   print "total fixed in time period: ", total_fixed_defects, "\n"
   print "total closed in time period: ", total_closed_defects, "\n"
   print "deferred: ", total_deferred, "\n"
   print "wsi: #{wsi}\n**********************************\n"
  
 
  
   html = "\n<div>\n"
   html << "<table id='defect-dashboard'>\n"
   html << "<tr><td>Open Defects</td><td>Defects Pending Verification</td><td>Closed Defects</td><td>Deferred Defects</td></tr>\n"
  
   html << "<tr>"
  
   html << "<td><div class='card'><span class='value'>#{current_open}</span><br><span class='label'>Total</span></div>"
   html << "<div class='card'><span class='value'>#{high_priority}</span><br><span class='label'>High Priority</span></div>\n"
   html << "<div class='card'><span class='value'>#{high_severity}</span><br><span class='label'>High Severity</span></div></td>\n"
  
   html << "<td><div class='card'><span class='value'>#{current_fixed}</span><br><span class='label'>Fixed</span></div>\n"
   html << "<div class='card'><span class='value'>#{current_cannotfix}</span><br><span class='label'>Cannot Fix</span></div></td>\n"
  
   html << "<td><div class='card'><span class='value'>#{current_closed}<span><br></div></td>\n"
   html << "<td><div class='card'><span class='value'>#{current_deferred}</span><br></div></td>\n"
  
   html << "</tr>\n"
  
   html << "</table>"
   html << "</div>\n\n"
   
   print "\ncurrent: open=", current_open, " fixed=", current_fixed, " cannot-fix=", current_cannotfix, " defer=", current_deferred, "\n"
  
   #html << render_hash("Resolution",closed_resolution_bucket)
   return html
end

# get all defects updated during sprint
def get_defects(rally,project,iteration)
  
   start_date=get_date(iteration.start_date)
   end_date=get_date(iteration.end_date)
  
   query_result=rally.find(:defect, :fetch => true, :project => project, :project_scope_up => false) {
      greater_than :last_update_date, start_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
      less_than :last_update_date, end_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
   }
  
   print "defects open OR updated since #{start_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')}: ", query_result.total_result_count, "\n"
  
   process_defects(query_result,start_date,end_date)
end

# get all defects currently open or which were updated during release
def get_release_defects(rally,project,release,wsi_hash)
  
   start_date=get_date(release.release_start_date)
   end_date=get_date(release.release_date)
  
   query_result=rally.find(:defect, :fetch => true, :project => project, :project_scope_up => false) {
      _or_ {
         _and_ {
            greater_than :last_update_date, start_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
            less_than :last_update_date, end_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
         }
         equal :state, "Open"
         equal :state, "Submitted"
      }
   }
  
   print "open defects and those updated since #{start_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')}: ", query_result.total_result_count, "\n"
  
   return process_defects(query_result,start_date,end_date,wsi_hash)
end

# main section

begin
   rally=RallyRestAPI.new(:username => LOGIN, :password => PASSWORD)
rescue Exception => ex
   puts "Error: Cannot connect to Rally"
   puts ex
   Process.exit(0)
end
  
project=rally.find(:project){equal :name, PROJECT_NAME}.first

release=rally.find(:release, :project => project, :fetch => true,
:project_scope_up => false,
:project_scope_down => true){equal :name, RELEASE_NAME}.first
     
puts "PROJECT: #{PROJECT_NAME} RELEASE: #{RELEASE_NAME}"
  
start_date=DateTime.parse(release.release_start_date)
end_date=DateTime.parse(release.release_date)
puts "release: #{start_date.strftime('%Y-%m-%d')} -> #{end_date.strftime('%Y-%m-%d')} (#{end_date.to_date()-start_date.to_date()} days)"
  
# write out all the defect stuff
   
File.open("results.csv",'w') { |file| file.write("DAY, CREATED, CLOSED, FIXED, WSI\n") }

# get the defects and wsi scores
  
# TODO: write this to an array
wsi_hash=Hash.new
defect_status_html=get_release_defects(rally,project,release,wsi_hash)
# wsi increases when a defect is opened, and decreases when a defect is closed
wsi_daily=[]
tmp=wsi_hash.to_a.sort
xwsi=0
cumul_fixed=0;

n=0
tmp.each { |item|
   record=item[1]
   xwsi=xwsi+record[:created]-record[:closed]
   #wsi=wsi+record[:created]-record[:fixed]
   wsi_daily.push([item[0],xwsi])

   line = "#{item[0].strftime('%Y-%m-%d')}, #{record[:created]}, #{record[:closed]}, #{record[:fixed]}, #{xwsi}\n"
   # text << "#{item[0].strftime('%Y-%m-%d')} CREATED=#{record[:created]} CLOSED=#{record[:closed]} FIXED=#{record[:fixed]} WSI=#{xwsi}\n"
     
   # head << "[#{item[0].to_time.to_i*1000}, #{xwsi}]"
     
   File.open("results.csv", 'a') { |file| file.write(line) }
      
   #print line
}
    
  