# A package whose own function calls its own helper.
def sp_helper()
  :bidama
end

def sp_call_helper()
  sp_helper()
end
