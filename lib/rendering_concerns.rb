require 'cgi'
module RenderingConcerns
  FACET_FIELDS = ['type', 'year', 'oa_status', 'publication', 'category', 'publisher', 'funder_name', 'source']

  def partial template, locals = nil
    haml template.to_sym, layout: false, locals: locals
  end

  def render_top_funder_name m, names
    top_funder_id = m.keys.first
    names[top_funder_id]
  end

  def render_top_funder_id m
    m.keys.first
  end

  def rest_funder_nesting m
    m[m.keys.first]
  end

  def render_funders m, names, indent, &block
    ks = m.keys
    ks.each do |k|
      if m[k].keys == ['more']
        block.call(indent + 1, k, names[k], true)
      else
        block.call(indent + 1, k, names[k], false)
        render_funders(m[k], names, indent + 1, &block)
      end
    end
  end

  def abstract_facet_query
    fq = {}
    FACET_FIELDS.each do |field|
      if params.has_key? field
        params[field].split(';').each do |val|
          fq[field] ||= []
          fq[field] << val
        end
      end
    end
    fq
  end

  def facet_link field_name, field_value
    fq = abstract_facet_query
    fq[field_name] ||= []
    fq[field_name] << field_value

    link = "#{request.path_info}?q=#{CGI.escape(params['q'])}"
    fq.each_pair do |field, vals|
      link += "&#{field}=#{CGI.escape(vals.join(';'))}"
    end
    link
  end

  def facet_link_not field_name, field_value
    fq = abstract_facet_query
    fq[field_name].delete field_value
    fq.delete(field_name) if fq[field_name].empty?

    link = "#{request.path_info}?q=#{CGI.escape(params['q'])}"
    fq.each_pair do |field, vals|
      link += "&#{field}=#{CGI.escape(vals.join(';'))}"
    end
    link
  end

  def search_link opts
    fields = FACET_FIELDS + ['q', 'sort']
    parts = fields.map do |field|
      if opts.has_key? field.to_sym
        "#{field}=#{CGI.escape(opts[field.to_sym])}"
      elsif params.has_key? field
        params[field].split(';').map do |field_value|
          "#{field}=#{CGI.escape(params[field])}"
        end
      end
    end

    "#{request.path_info}?#{parts.compact.flatten.join('&')}"
  end
end
