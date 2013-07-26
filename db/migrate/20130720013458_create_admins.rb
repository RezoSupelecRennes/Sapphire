# -*- encoding : utf-8 -*-
class CreateAdmins < ActiveRecord::Migration
  def change
    create_table :admins do |t|

      t.string     :password_hash, null: false
      t.string     :password_salt, null: false

      t.string     :username, null: false, index: true
      
      t.integer    :adherent_id, null: false, index: true

      t.boolean    :archived, default: false
      t.datetime   :last_login
      t.timestamps
    end
  end
end
