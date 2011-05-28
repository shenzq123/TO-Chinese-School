class RegistrationPayment < ActiveRecord::Base

  belongs_to :school_year
  belongs_to :paid_by, :class_name => 'Person', :foreign_key => 'paid_by_id'
  has_many :student_fee_payments

  validates_presence_of :school_year, :paid_by, :pva_due_in_cents, :ccca_due_in_cents

  validates_numericality_of :pva_due_in_cents, :only_integer => true, :allow_nil => false
  validates_numericality_of :ccca_due_in_cents, :only_integer => true, :allow_nil => false
  validates_numericality_of :grand_total_in_cents, :only_integer => true, :allow_nil => false

  
  def fill_in_due
    self.pva_due_in_cents = calculate_pva_due
    self.ccca_due_in_cents = calculate_ccca_due
  end
  
  def calculate_grand_total
    self.grand_total_in_cents = self.pva_due_in_cents + self.ccca_due_in_cents
    self.student_fee_payments.each do |student_fee_payment|
      self.grand_total_in_cents = self.grand_total_in_cents + student_fee_payment.total_in_cents
    end
  end
  
  private
  
  def calculate_pva_due
    # PVA membership due is up to 2 parents per family
    if self.student_fee_payments.size > 1
      self.school_year.pva_membership_due_in_cents * 2
    else
      self.school_year.pva_membership_due_in_cents
    end
  end

  def calculate_ccca_due
    return 0 if self.paid_by.families.detect { |family| family.ccca_lifetime_member? }
    self.school_year.ccca_membership_due_in_cents
  end
end