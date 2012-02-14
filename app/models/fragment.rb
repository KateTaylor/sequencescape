class Fragment < Asset
  include LocationAssociation::Locatable

  self.inheritance_column = "sti_type"

end
