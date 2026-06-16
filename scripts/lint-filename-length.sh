#!/usr/bin/env bash

# Exact value of maximum length is chosen as a "reasonably high but not bigger
# than 143 (maximum filename length on eCryptfs systems) number".
# Having low-ish value also helps with restrictions on full path length.
max_filename_length=125

exit_code=0
for filename in $(find . -not -path './.git/**' -not -path './dual/**' -printf %f\\n); do
  if [ "${#filename}" -gt $max_filename_length ]; then
    echo "Too long file name: $filename"
    exit_code=1
  fi
done

exit $exit_code
