#!/bin/zsh
# Wakes macOS's Photos/Spotlight scanners if a test was force-quit while they were paused.
for p in mediaanalysisd photoanalysisd photolibraryd cloudphotod corespotlightd mdworker_shared mdworker textunderstandingd duetexpertd suggestd knowledgeconstructiond searchpartyd; do
  pkill -CONT -x -U $UID "$p" 2>/dev/null
done
sudo -n pkill -CONT -x mds 2>/dev/null; sudo -n pkill -CONT -x mds_stores 2>/dev/null
print "Photos/Spotlight scanning resumed."
