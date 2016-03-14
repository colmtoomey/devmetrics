# get all the defects updated during release and check the revision history for each to:
#
# 1. figure out how wsi is changing on a weekly basis
# 2. get activity lists (who created, fixed, closed)
#

# sudo gem install rally_rest_api [ add to gem file ]

PROJECT_NAME=ENV["RALLY_PROJECT_NAME"]
RELEASE_NAME=ENV["RALLY_RELEASE_NAME"]

LOGIN=ENV["RALLY_LOGIN"]
PASSWORD=ENV["RALLY_PASSWORD"]

# compile regular expressions
# Scheduled User Story [US4345: Enhance System Health - Status & Message in  System Health  for VPM overloading]
SCHEDULED_RE=/Scheduled User Story \[(US[0-9\.]+)/
UNSCHEDULED_RE=/Unscheduled User Story \[(US[0-9\.]+)/

FIXED_RE=/STATE changed from \[[A-Za-z ]*\] to \[Fixed\]/
CLOSED_RE=/STATE changed from \[[A-Za-z ]*\] to \[Closed\]/

ENV['RAILS_ENV'] ||= 'development'


require 'rally_rest_api'
require 'date'
require 'pp'

def incremental_average(previousAverage,value,nvalues)
   return(((value-previousAverage)/(nvalues+1))+previousAverage)
end

# convert a rally UTC date to a ruby date
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

   starting_wsi=0
   starting_wsi_list=[]
  
   defect_list.each do |defect|
  
      last_updated=get_date(defect.last_update_date)
      created_date=get_date(defect.creation_date)
      createdby=nil
      severity=get_wsi(defect)
     
      # 'created' calculations include defects modified during project but created before it started - wsi for those defects goes into start week
      if (!created_date.nil? && created_date<=end_date)
         
         if (created_date>=start_date)
            total_created_defects=total_created_defects+1
         end
         
         thedate=created_date
         if (created_date<start_date)
            # created before start date so we'll count it in the first week - not sure this is correct! should only be in WSI if start was open/fixed/cannot-fix/deferred at this time
            thedate=start_date
            starting_wsi=starting_wsi+severity
            starting_wsi_list << { :id => "#{defect.formatted_i_d}", :state => "#{defect.state}", :severity => "#{severity}" }
         end

         # bucket data into commercial weeks
         d=Date.commercial(thedate.cwyear,thedate.cweek,1)
         
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

         # we always see most recent revision first
       
         #puts "#{revision.revision_number} #{get_date(revision.creation_date).strftime('%Y-%m-%d')}"

         if (revision.description=='Original revision')
            # already got creation date, check who created the defect
            createdby=revision.user
         elsif (defect.state=="Fixed" || defect.state=="Closed")

            # check if this is X->Fixed transition - only count most recent instance of the transition (the first one we see)
            m=nil
            if (fixed_date.nil?)
               m=FIXED_RE.match(revision.description)
               if (m)
                  thefixer=revision.user
                  #if ($fixed_statistics[thefixer].nil?)
                  #   $fixed_statistics[thefixer]=Array.new();
                  #end
                  #$fixed_statistics[thefixer] << defect
              
                  fixed_date=get_date(revision.creation_date)
                  if (!fixed_date.nil? && fixed_date>=start_date && fixed_date<=end_date)
                     # we only care if it was fixed during the release date interval
                     total_fixed_defects=total_fixed_defects+1

                     if (fixed_date<start_date)
                           #puts "************* found something that was FIXED before project start!!!!!!!! #{defect.formatted_i_d}"
                           closed_date=start_date
                        end
                 
                     # add to the wsi hash
                  
                     # bucket data into commercial weeks
                     d=Date.commercial(fixed_date.cwyear,fixed_date.cweek,1)
                  
                     record=wsi_hash[d]
                     if (record)
                        record[:fixed]=record[:fixed]+severity
                     else
                        wsi_hash[d]={ :created => 0, :fixed => severity, :closed => 0 }
                     end
                  end
               end
            end

            # check if this is X->Closed transition - don't count stuff that was reopened, only count most recent instance of transition (the first one we see)
            if (m.nil? && closed_date.nil? && defect.state=="Closed")
               m=CLOSED_RE.match(revision.description)
               if (m)
                  # get closed date
                  closedby=revision.user
                  closed_date=get_date(revision.creation_date)
                  if (!closed_date.nil? && closed_date<=end_date)
                     
                     if (closed_date>=start_date)
                        total_closed_defects=total_closed_defects+1
                     end
                        
                        # bucket data into commercial weeks
                        if (closed_date<start_date)
                           #puts "************* found something that closed before project start!!!!!!!! #{defect.formatted_i_d}"
                           closed_date=start_date
                        end
                        d=Date.commercial(closed_date.cwyear,closed_date.cweek,1)
                        
                        record=wsi_hash[d]
                        if (record)
                           record[:closed]=record[:closed]+severity
                        else
                           wsi_hash[d]={ :created => 0, :fixed => 0, :closed => severity }
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

   puts "starting wsi=#{starting_wsi}"
   pp starting_wsi_list;

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

   #start_date=DateTime.new(2016,2,29)
   end_date=get_date(release.release_date)
  
   query_result=rally.find(:defect, :fetch => true, :project => project, :project_scope_up => false) {
      _or_ {
         _and_ {
            greater_than :last_update_date, start_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
            less_than :last_update_date, end_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')
         }
         # used to be equal :state, "Submitted" and "Open"
         less_than :state, "Closed"
      }
   }
  
   print "open defects and those updated since #{start_date.strftime('%Y-%m-%dT%H:%M:%S.000Z')}: ", query_result.total_result_count, "\n"
  
   return process_defects(query_result,start_date,end_date,wsi_hash)
end

# main section

require 'yaml'
require 'active_record'
require './app/models/defect_trend_by_week'


configuration = YAML::load(IO.read('config/database.yml'))
ActiveRecord::Base.establish_connection(configuration['development'])

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
   
start_date=DateTime.parse(release.release_start_date)
end_date=DateTime.parse(release.release_date)
puts "release: #{start_date.strftime('%Y-%m-%d')} -> #{end_date.strftime('%Y-%m-%d')} (#{end_date.to_date()-start_date.to_date()} days)"

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

   week_record=DefectTrendByWeek.find_or_initialize_by(day: item[0].strftime('%Y-%m-%d'))
   week_record.created=record[:created]
   week_record.fixed=record[:fixed]
   week_record.closed=record[:closed]
   week_record.wsi=xwsi
   week_record.save



   # text << "#{item[0].strftime('%Y-%m-%d')} CREATED=#{record[:created]} CLOSED=#{record[:closed]} FIXED=#{record[:fixed]} WSI=#{xwsi}\n"
     
   # head << "[#{item[0].to_time.to_i*1000}, #{xwsi}]"
     
   #File.open("results.csv", 'a') { |file| file.write(line) }
      
   print line
}
    
  